module Push
  # 朝のダイジェスト。前の回以降に届いた未読の本数を題に、新しい順の見出しを本文にする。
  # Claude による選定が入るまでの代替（ADR 0013）。新着が無い朝は出さない（空の通知で呼ばない）。
  # 本文に載せる本数は dopamine.yml の push.digest_articles。無ければ題だけ
  class Digest < Notice
    # 本文の上限バイト数。Web Push の本文は暗号化後 4096 バイトまで（RFC 8291、web-push が ArgumentError で止める）で、
    # 超えると送れない文面をその日中 10 分おきに作り直す。見出しの長さは外から来るので、プロトコルの制約に余裕をみた固定値で切る
    BODY_BYTES = 1024

    def self.time_key
      :digest_at
    end

    def self.sent_on_column
      :digest_sent_on
    end

    def payload
      # 「前の回」は 1 日 1 回なので 24 時間前。窓の広さの調整値ではなく回数から決まる
      articles = Article.unread.where(created_at: (due_at - 1.day)..).newest_first
      count = articles.count
      return if count.zero?

      { title: "今日の新着 #{count} 本が届きました", body: headlines(articles), path: "/", unread: unread_count, tag: "digest" }
    end

    private

    def headlines(articles)
      limit = Dopamine.settings.dig(:push, :digest_articles)
      articles.limit(limit).pluck(:title).join("\n").truncate_bytes(BODY_BYTES) if limit
    end
  end
end
