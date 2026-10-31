require "test_helper"

class ArticleTest < ActiveSupport::TestCase
  test "feed, title, url が必須" do
    article = Article.new
    assert_not article.valid?
    assert_includes article.errors[:feed], "must exist"
    assert_includes article.errors[:title], "can't be blank"
    assert_includes article.errors[:url], "can't be blank"
  end

  test "url は一意" do
    existing = articles(:rails_81)
    dup = Article.new(feed: existing.feed, title: "別名", url: existing.url)
    assert_not dup.valid?
    assert_includes dup.errors[:url], "has already been taken"
  end

  test "summary が無くても保存できる（要約は Unit 4 の Job が付ける）" do
    article = Article.new(feed: feeds(:rails_blog), title: "未要約", url: "https://example.com/rails/unsummarized")
    assert article.valid?
  end

  test "content, guid, liked_at, bookmarked_at は無くてもよい（Unit 3 以降が埋める）" do
    article = Article.new(feed: feeds(:rails_blog), title: "最小", url: "https://example.com/rails/minimal")
    assert article.valid?
    assert_nil article.content
    assert_nil article.guid
    assert_not article.saved?
  end

  test "unread は完読した記事を除く。開いただけの記事は未読のまま" do
    unread = Article.unread.to_a
    assert_not_includes unread, articles(:rails_81), "完読済みは出ない"
    assert_includes unread, articles(:weekly_770), "開いたが未完は未読のまま（出目は Reading に残る）"
    assert_includes unread, articles(:rails_82), "一度も開いていない"
  end

  test "read は完読した記事だけ" do
    assert_equal [ articles(:rails_81) ], Article.read.to_a
  end

  test "saved は liked_at か bookmarked_at のある記事" do
    bookmarked = articles(:weekly_770)
    bookmarked.update!(bookmarked_at: Time.current)

    assert_equal [ articles(:rails_82), bookmarked ].sort, Article.saved.sort
    assert articles(:rails_82).saved?
    assert bookmarked.saved?
    assert_not articles(:rails_81).saved?
  end

  test "newest_first は published_at の新しい順" do
    assert_equal [ articles(:weekly_770), articles(:rails_82), articles(:rails_81) ], Article.newest_first.to_a
  end

  test "記事を消すと読了も消える" do
    article = articles(:rails_81)
    assert_difference("Reading.count", -1) { article.destroy! }
  end
end
