module Claude
  # 月曜の決まった時刻に 1 回だけ積むと、その時刻に止まっていた週は書かれない。毎時積んで、行の無い週だけを呼ぶ。
  class WeeklyCommentJob < BaseJob
    retry_on WeeklyCommenter::TransientError, wait: :polynomially_longer do |job, error|
      WeeklyComment.record_failure!(job.week_start, error.message)
    end

    limits_concurrency key: ->(*) { "weekly_comment" }

    attr_reader :week_start

    def perform(week_start = nil)
      @week_start = week_start || WeeklyReport.new.start_day - WeeklyReport::DAYS
      # 再試行は arguments から積み直す。週を固定しないと、再試行が月曜をまたいだとき別の週を呼ぶ
      self.arguments = [ @week_start ]
      row = WeeklyComment.find_by(week_start: @week_start)
      return if row && !(row.pending? && row.job_id == job_id)

      report = WeeklyReport.new(today: @week_start + (WeeklyReport::DAYS - 1))
      return if report.count.zero?

      @claim = row || WeeklyComment.create!(week_start: @week_start, job_id: job_id)
      commenter = WeeklyCommenter.new(report)
      @claim.update!(body: commenter.call, model: commenter.model)
    rescue ActiveRecord::RecordNotUnique
      nil
    rescue WeeklyCommenter::TransientError
      raise
    rescue WeeklyCommenter::Error => e
      WeeklyComment.record_failure!(@week_start, e.message)
    rescue StandardError
      # 予算切れや鍵の欠けで押さえたまま終えると、その週は二度と呼ばれない。外して後の回に任せる
      @claim&.destroy
      raise
    end
  end
end
