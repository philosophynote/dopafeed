module Claude
  # 本文なし・形式不正・4xx は時間を置いても解消しないため、自動では再試行しない。
  # 重複を discard すると再試行の待ち時間中に鍵が奪われ、再試行本体まで捨てられて失敗を記録できない。
  # semaphore の期限切れや再試行中の鍵の解放により、重複実行の API 料金までは防げない。
  class SummarizeArticleJob < BaseJob
    discard_on ActiveJob::DeserializationError do |job, error|
      Rails.logger.info("[claude] #{job.class.name} discarded: #{error.message}")
    end

    retry_on Summarizer::TransientError, wait: :polynomially_longer do |job, error|
      record_failure(job.arguments.first, error.message)
    end

    limits_concurrency key: ->(article) { article.id }

    def self.enqueue_if_awaiting(article)
      perform_later(article) if Article.awaiting_summary.exists?(article.id)
    end

    def perform(article)
      return unless Article.awaiting_summary.exists?(article.id)

      summary = Summarizer.new(article).call
      article.reload.with_lock do
        article.update!(summary: summary, summary_failed_at: nil, summary_error: nil) if article.summary.blank?
      end
      self.class.broadcast(article)
    rescue Summarizer::TransientError
      raise
    rescue Summarizer::Error => e
      self.class.record_failure(article, e.message)
    rescue Budget::Exhausted
      # 捨てるのは親の discard_on。その前に知らせないと、待っている側は出来上がりを待ち続ける
      self.class.broadcast(article)
      raise
    end

    # 失敗の記録も、先に要約を付けた実行があれば上書きしない
    def self.record_failure(article, message)
      article.with_lock do
        article.update!(summary_failed_at: Time.current, summary_error: message) if article.summary.blank?
      end
      broadcast(article)
    end

    # 読み直してから描く。重なった別の実行が先に要約を書いていれば、そちらを出す（古い記事で上書きしない）
    def self.broadcast(article)
      article.reload
      Turbo::StreamsChannel.broadcast_replace_to(article, :summary, target: ActionView::RecordIdentifier.dom_id(article, :summary_box),
                                                                    partial: "articles/summary", locals: { article: article })
    end
  end
end
