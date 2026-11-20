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
      # 押し直しで積まれた分も、待っている側が出来上がりを受け取れるよう知らせてから終わる
      return self.class.broadcast(article) if article.persona_comments.exists?

      bodies = Commenter.new(article).call
      article.with_lock do
        next if article.persona_comments.exists?

        now = Time.current
        PersonaComment.insert_all!(bodies.map { |persona_id, body| { article_id: article.id, persona_id:, body:, created_at: now, updated_at: now } })
        article.update!(comments_failed_at: nil, comments_error: nil)
      end
      self.class.broadcast(article)
    rescue Commenter::TransientError
      raise
    rescue Commenter::Error => e
      self.class.record_failure(article, e.message)
    rescue Claude::Budget::Exhausted
      # 捨てるのは親の discard_on。頼んだ印を残すと、読み直しても待ち状態のまま残る
      article.update!(comments_requested_at: nil)
      self.class.broadcast(article, exhausted: true)
      raise
    rescue StandardError => e
      # 設定の誤りは畳まずに上げるが、記録しないと頼んだ印だけが残り、押し直す手段が無くなる。
      # 例外の文面は SQL や要求を含みうるので、クラス名だけを残す
      self.class.record_failure(article, "予期しない失敗 (#{e.class.name.demodulize})")
      raise
    end

    def self.record_failure(article, message)
      article.with_lock do
        article.update!(comments_failed_at: Time.current, comments_error: message) unless article.persona_comments.exists?
      end
      broadcast(article)
    end

    # 重なった別の実行が先に保存していれば、失敗や上限ではなくそちらを出す
    def self.broadcast(article, exhausted: false)
      article.reload
      Turbo::StreamsChannel.broadcast_replace_to(article, :comments, target: ActionView::RecordIdentifier.dom_id(article, :comments_box),
                                                                     partial: "comments/box", locals: { article: article, exhausted: exhausted })
    end
  end
end
