module Comments
  # 予算切れの扱いと claude キューは要約と共用する（日次上限は AI の呼び出し全体で一つ）。
  # 本文なし・形式不正・4xx は時間を置いても解消しないため、自動では再試行しない。押し直しは利用者に任せる。
  class CommentArticleJob < Claude::BaseJob
    discard_on ActiveJob::DeserializationError do |job, error|
      Rails.logger.info("[comments] #{job.class.name} discarded: #{error.message}")
    end

    retry_on Commenter::TransientError, wait: :polynomially_longer do |job, error|
      record_failure(job.arguments.first, error.message)
    end

    limits_concurrency key: ->(article) { article.id }

    def perform(article)
      return if article.persona_comments.exists?

      bodies = Commenter.new(article).call
      article.with_lock do
        next if article.persona_comments.exists?

        now = Time.current
        PersonaComment.insert_all!(bodies.map { |persona_id, body| { article_id: article.id, persona_id:, body:, created_at: now, updated_at: now } })
        article.update!(comments_failed_at: nil, comments_error: nil)
      end
    rescue Commenter::TransientError
      raise
    rescue Commenter::Error => e
      self.class.record_failure(article, e.message)
    end

    # 失敗の記録も、先に保存した実行があれば残さない
    def self.record_failure(article, message)
      article.with_lock do
        article.update!(comments_failed_at: Time.current, comments_error: message) unless article.persona_comments.exists?
      end
    end
  end
end
