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

  # 日数の鍵が無い区分は消さない。消した記事は戻せないので、設定の書き漏れで消えるより残る方を選ぶ。
  # in_batches が渡す batch は rewhere(id:) で id の条件（完読の除外）を落とすため、条件は expired から組み直す。
  def purge(reason, key)
    days = Dopamine.settings.dig(:retention, key)
    return 0 if days.nil?

    expired = keepable_excluded(yield(now - days.days))
    expired.in_batches.sum { |batch| purge_batch(expired.where(id: batch.ids), reason) }
  end

  # 前の読書日から開いた・戻った記事を消すと、読んでいる途中の記事が消え、
  # 今日の連続を切っていた未完の行が消えて「n 連続」が伸びる。
  def keepable_excluded(scope)
    touched = Reading.where(opened_at: recent..).or(Reading.where(returned_at: recent..))
    scope.where(liked_at: nil, bookmarked_at: nil)
         .where.not(id: Reading.completed.select(:article_id))
         .where.not(id: touched.select(:article_id))
  end

  def recent
    @recent ||= ReadingDay.range(ReadingDay.of(now).prev_day).begin
  end

  # 抜き出してから書き込みのロックを取るまでに保存・完読が付いた記事を消さないよう、トランザクションの中で引き直す。
  # 判定の行は外部キーの on_delete: :cascade で消える。
  def purge_batch(candidates, reason)
    Article.transaction do
      rows = candidates.pluck(:id, :feed_id, :guid, :url)
      next 0 if rows.empty?

      ids = rows.map(&:first)
      PurgedArticle.insert_all(rows.map { |_, feed_id, guid, url| { feed_id: feed_id, guid: guid, url: url, reason: reason, purged_at: now } })
      Reading.where(article_id: ids).delete_all
      Article.where(id: ids).delete_all
    end
  end
end
