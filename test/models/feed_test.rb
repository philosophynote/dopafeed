require "test_helper"

class FeedTest < ActiveSupport::TestCase
  test "title と url が必須" do
    feed = Feed.new
    assert_not feed.valid?
    assert_includes feed.errors[:title], "can't be blank"
    assert_includes feed.errors[:url], "can't be blank"
  end

  test "url は一意" do
    existing = feeds(:rails_blog)
    dup = Feed.new(title: "別名", url: existing.url)
    assert_not dup.valid?
    assert_includes dup.errors[:url], "has already been taken"
  end

  test "削除すると記事も消える" do
    feed = feeds(:rails_blog)
    assert_difference("Article.count", -feed.articles.count) { feed.destroy! }
  end
end
