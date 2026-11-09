class FeedRegistration
  Result = Data.define(:feed, :message)

  def self.call(input)
    uri = URI(input.to_s.strip)
    uri.fragment = nil
    url = uri.to_s
    existing = Feed.find_by(url: url)
    return Result.new(existing, "登録済み") if existing

    discovered = FeedDiscovery.call(url) { |candidate| Feed.exists?(url: candidate) }
    url = discovered.url
    existing = Feed.find_by(url: url)
    return Result.new(existing, "登録済み") if existing

    feed = Feed.create!(url: url, title: discovered.title)
    message = enqueue(feed) ? "記事を取得しています" : "記事の取得は後ほど再試行します"
    Result.new(feed, "「#{feed.title}」を追加しました。#{message}")
  rescue URI::Error
    Result.new(nil, "URL が正しくありません")
  rescue HttpGet::Error => e
    Result.new(nil, e.message)
  rescue FeedDocument::Error, FeedDiscovery::Error => e
    Result.new(nil, e.message)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    existing = Feed.find_by(url: url)
    raise unless existing

    Result.new(existing, "登録済み")
  end

  # 未コミットの購読をワーカーが捨てないよう、保存の後に予約する。失敗時も定期取得で拾えるよう登録は残す。
  def self.enqueue(feed)
    FetchFeedJob.perform_later(feed).present?
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError, ActiveRecord::ActiveRecordError
    false
  end
  private_class_method :enqueue
end
