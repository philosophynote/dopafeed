# 本文なし・形式不正は時間を置いても解消しないため、自動では再試行しない。
# 予算切れと、4xx で拒まれた要求（鍵・残高・モデル名・要求の形）は行を残さず捨てる。記事のせいではない失敗を記事に残すと、直した後に開き直しても判定されない。
class JudgeArticleJob < ApplicationJob
  queue_as :judgments

  discard_on Claude::Budget::Exhausted, Judgments::ArticleScorer::RejectedError, ActiveJob::DeserializationError do |job, error|
    Rails.logger.warn("[judgments] #{job.class.name} discarded: #{error.message}")
  end

  retry_on Judgments::ArticleScorer::TransientError, wait: :polynomially_longer do |job, error|
    record(job.arguments.first, { failed_at: Time.current, error: error.message })
  end

  limits_concurrency key: ->(article) { article.id }

  def self.enqueue_if_awaiting(article)
    perform_later(article) if Judgments::ArticleScorer.configured? && Article.awaiting_judgment.exists?(article.id)
  end

  def perform(article)
    return unless Article.awaiting_judgment.exists?(article.id)

    result = Judgments::ArticleScorer.new(article).call
    self.class.record(article, result.scores.merge(result.to_h.except(:scores), judged_at: Time.current))
  rescue Judgments::ArticleScorer::TransientError, Judgments::ArticleScorer::RejectedError
    raise
  rescue Judgments::ArticleScorer::Error => e
    self.class.record(article, { failed_at: Time.current, error: e.message })
  end

  # 重なった別の実行が先に書いていたら、先の結果を残す（記事 1 本に 1 行。DB の一意制約）。
  # 呼んでいる間に記事が消えていたら、残す先が無い。
  def self.record(article, attributes)
    ArticleJudgment.create!(article: article, **attributes)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey
    nil
  end
end
