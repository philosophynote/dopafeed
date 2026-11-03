module Claude
  # 記事 1 本に 3 行要約を付ける。要約済みなら呼ばない（二度払いしない）。
  # 失敗は例外にせず articles.summary_failed_at / summary_error に残し、自動では再試行しない（本文なし・形式不正・4xx は時間が解決しない）。
  # 待てば通るかもしれない失敗（{Summarizer::TransientError}）だけ ActiveJob の既定の回数・間隔でやり直し、尽きたら同じ列に記録する。
  # 同じ記事の Job が重なったら 2 本目を捨てる（定期ジョブが、まだ走っていない前回の積み残しをもう一度積むことがある）。
  # Solid Queue の semaphore は既定の期間で失効するので、それより長く滞留した記事は 2 本とも走りうる。そのときも要約は 1 回分しか残さない
  # （呼ぶ直前に読み直し、書く直前に鍵を取って確かめる）。余分に払うのは台帳 1 行まで。
  # 記事が消えていたら捨てる（要約する相手がいない）
  class SummarizeArticleJob < BaseJob
    discard_on ActiveJob::DeserializationError do |job, error|
      Rails.logger.info("[claude] #{job.class.name} discarded: #{error.message}")
    end

    retry_on Summarizer::TransientError, wait: :polynomially_longer do |job, error|
      job.arguments.first.update!(summary_failed_at: Time.current, summary_error: error.message)
    end

    limits_concurrency key: ->(article) { article.id }, on_conflict: :discard

    def perform(article)
      return if article.reload.summary.present?

      summary = Summarizer.new(article).call
      article.with_lock do
        article.update!(summary: summary, summary_failed_at: nil, summary_error: nil) if article.summary.blank?
      end
    rescue Summarizer::TransientError
      raise
    rescue Summarizer::Error => e
      article.update!(summary_failed_at: Time.current, summary_error: e.message)
    end
  end
end
