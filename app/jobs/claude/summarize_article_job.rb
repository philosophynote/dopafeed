module Claude
  # 記事 1 本に 3 行要約を付ける。要約済みなら呼ばない（二度払いしない）。
  # 失敗は例外にせず articles.summary_failed_at / summary_error に残し、自動では再試行しない。本文なし・形式不正・4xx は時間が解決しないので、
  # 人が summary_failed_at を nil に戻したときだけ {SummarizePendingArticlesJob} が拾い直す。
  # 待てば通るかもしれない失敗（{Summarizer::TransientError}）だけ ActiveJob の既定の回数・間隔でやり直し、尽きたら同じ列に記録する。
  # 同じ記事の Job が重なったら 2 本目を捨てる（定期ジョブが、まだ走っていない前回の積み残しをもう一度積むことがある）。
  # 記事が消えていたら捨てる（要約する相手がいない）
  class SummarizeArticleJob < BaseJob
    discard_on ActiveJob::DeserializationError do |job, error|
      Rails.logger.info("[claude] #{job.class.name} discarded: #{error.message}")
    end

    retry_on Summarizer::TransientError, wait: :polynomially_longer do |job, error|
      job.arguments.first.update!(summary_failed_at: Time.current, summary_error: error.message)
    end

    limits_concurrency key: ->(article) { article.id }, on_conflict: :discard

    # @param article [Article]
    def perform(article)
      return if article.summary.present?

      article.update!(summary: Summarizer.new(article).call, summary_failed_at: nil, summary_error: nil)
    rescue Summarizer::TransientError
      raise
    rescue Summarizer::Error => e
      article.update!(summary_failed_at: Time.current, summary_error: e.message)
    end
  end
end
