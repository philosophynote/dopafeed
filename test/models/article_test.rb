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
end
