# 保存した記事と完読した記事（カード）は日数を過ぎても消さない。
# 日数の鍵が無い区分は消さない。消した記事は戻せないので、設定の書き漏れで消えるより残る方を選ぶ。
class ArticleRetention
  Result = Data.define(:dismissed, :unread)

  def self.call(now: Time.current)
    new(now).call
  end

  def initialize(now)
    @now = now
  end

  def call
    Result.new(
      dismissed: purge("dismissed", :dismissed_days) { |cutoff| Article.where(dismissed_at: ..cutoff) },
      unread: purge("unread", :unread_days) { |cutoff| Article.unread.where(created_at: ..cutoff) }
    )
  end

  private

  attr_reader :now

  def purge(reason, key)
    days = Dopamine.settings.dig(:retention, key)
    return 0 if days.nil?

    expired = keepable_excluded(yield(now - days.days))
    expired.in_batches.sum { |batch| purge_batch(batch, reason) }
  end

  def keepable_excluded(scope)
    scope.where(liked_at: nil, bookmarked_at: nil).where.not(id: Reading.completed.select(:article_id))
  end

  # 抜き出してから消すまでの間に保存・完読が付くと、それを消してしまう。条件を持ったままの batch をトランザクションの中で引き直す。
  # 判定の行は外部キーの on_delete: :cascade で消える。
  def purge_batch(batch, reason)
    Article.transaction do
      rows = batch.pluck(:id, :feed_id, :guid, :url)
      next 0 if rows.empty?

      ids = rows.map(&:first)
      PurgedArticle.insert_all(rows.map { |_, feed_id, guid, url| { feed_id: feed_id, guid: guid, url: url, reason: reason, purged_at: now } })
      Reading.where(article_id: ids).delete_all
      Article.where(id: ids).delete_all
    end
  end
end
