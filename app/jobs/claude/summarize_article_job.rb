module Claude
  # 記事 1 本に 3 行要約を付ける。積むのは「読む」で行ができた記事だけ（{.enqueue_if_awaiting}。読まない記事に払わない）。
  # 要約済み・失敗を記録済みなら呼ばない（二度払いしない。失敗をやり直すのは人が戻したときだけ）。
  # 失敗は例外にせず articles.summary_failed_at / summary_error に残し、自動では再試行しない（本文なし・形式不正・4xx は時間が解決しない）。
  # 待てば通るかもしれない失敗（{Summarizer::TransientError}）だけ ActiveJob の既定の回数・間隔でやり直し、尽きたら同じ列に記録する。
  # 同じ記事の Job は 1 本ずつ走らせ、重なった分は待たせる（「読む」の押し直しと本文取得の後とで、同じ記事が二度積まれることがある）。
  # 待たされた方は走ったときに要約済みか失敗を記録済みなので何もしない。捨てる（on_conflict: :discard）と、やり直しの待ち時間中に積まれた重複が
  # 鍵を取り、やり直し本体が捨てられて「尽きたら記録する」が走らなくなる。
  # Solid Queue の semaphore は既定の期間で失効するので、それより長く滞留した記事は 2 本とも走りうる。そのときも要約は 1 回分しか残さない
  # （呼ぶ直前に読み直し、書く直前に鍵を取って確かめる）。余分に払うのは台帳 1 行まで。
  # 記事が消えていたら捨てる（要約する相手がいない）。
  # 人は要約を待っているので、書き終え・失敗・予算切れのたびに要約欄を Turbo Stream で差し替える
  class SummarizeArticleJob < BaseJob
    discard_on ActiveJob::DeserializationError do |job, error|
      Rails.logger.info("[claude] #{job.class.name} discarded: #{error.message}")
    end

    retry_on Summarizer::TransientError, wait: :polynomially_longer do |job, error|
      record_failure(job.arguments.first, error.message)
    end

    limits_concurrency key: ->(article) { article.id }

    # @return [Boolean] 積んだか
    def self.enqueue_if_awaiting(article)
      return false unless Article.awaiting_summary.exists?(article.id)

      perform_later(article)
      true
    end

    def perform(article)
      article.reload
      return if article.summary.present? || article.summary_failed_at.present?

      summary = Summarizer.new(article).call
      article.with_lock do
        article.update!(summary: summary, summary_failed_at: nil, summary_error: nil) if article.summary.blank?
      end
      self.class.broadcast(article)
    rescue Summarizer::TransientError
      raise
    rescue Summarizer::Error => e
      self.class.record_failure(article, e.message)
    rescue Budget::Exhausted
      # 捨てるのは親の discard_on。その前に「作成中」のままにしない
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

    def self.broadcast(article)
      Turbo::StreamsChannel.broadcast_replace_to(article, :summary, target: ActionView::RecordIdentifier.dom_id(article, :summary),
                                                                    partial: "articles/summary", locals: { article: article })
    end
  end
end
