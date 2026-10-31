RSpec.describe Article, type: :model do
  it "feed, title, url が必須" do
    article = Article.new
    expect(article).not_to be_valid
    expect(article.errors[:feed]).to include("must exist")
    expect(article.errors[:title]).to include("can't be blank")
    expect(article.errors[:url]).to include("can't be blank")
  end

  it "url は一意" do
    existing = create(:article)
    dup = Article.new(feed: existing.feed, title: "別名", url: existing.url)
    expect(dup).not_to be_valid
    expect(dup.errors[:url]).to include("has already been taken")
  end

  it "summary が無くても保存できる（要約は Unit 4 の Job が付ける）" do
    expect(build(:article, :unsummarized)).to be_valid
  end
end
