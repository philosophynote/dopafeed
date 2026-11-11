module Push
  class Digest < Notice
    # 暗号化後の上限は 4096 バイト（RFC 8291）。超えるとその日中送れないため、外部の見出しを余裕のある固定長で切る。
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
