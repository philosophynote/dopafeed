module Claude
  # 毎時積まれ、終わった週の行がまだ無いときだけ呼ぶ。月曜に止まっていても次の回で追いつく。
  class WeeklyCommentJob < BaseJob
    retry_on WeeklyCommenter::TransientError, wait: :polynomially_longer do |job, error|
      WeeklyComment.record_failure!(job.week_start, error.message)
    end

    limits_concurrency key: ->(*) { "weekly_comment" }

    attr_reader :week_start

    def perform(week_start = nil)
      @week_start = week_start || WeeklyReport.new.start_day - WeeklyReport::DAYS
      return if WeeklyComment.exists?(week_start: @week_start)

      report = WeeklyReport.new(today: @week_start + (WeeklyReport::DAYS - 1))
      return if report.count.zero?

      WeeklyComment.create!(week_start: @week_start, body: WeeklyCommenter.new(report).call)
    rescue ActiveRecord::RecordNotUnique
      nil
    rescue WeeklyCommenter::TransientError
      raise
    rescue WeeklyCommenter::Error => e
      WeeklyComment.record_failure!(@week_start, e.message)
    end
  end
end
