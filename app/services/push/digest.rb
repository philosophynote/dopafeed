module Push
  # 朝のダイジェスト。前の回（24 時間前）以降に届いた未読の本数を題に、新しい順の見出しを本文にする。
  # Claude による選定が入るまでの代替で、タップ先は Main（ADR 0013）。新着が無い朝は出さない（空の通知で呼ばない）。
  # 本文に載せる本数は dopamine.yml の push.digest_articles。無ければ題だけ
  class Digest < Notice
    def self.time_key
      :digest_at
    end

    def self.sent_on_column
      :digest_sent_on
    end

    def payload
      articles = Article.unread.where(created_at: (due_at - 1.day)..).newest_first
      count = articles.count
      return if count.zero?

      { title: "今日の新着 #{count} 本が届きました", body: headlines(articles), path: "/", unread: unread_count, tag: "digest" }
    end

    private

    def headlines(articles)
      limit = Dopamine.settings.dig(:push, :digest_articles)
      articles.limit(limit).pluck(:title).join("\n") if limit
    end
  end
end
