RSpec.describe Feed, type: :model do
  it "title と url が必須" do
    feed = Feed.new
    expect(feed).not_to be_valid
    expect(feed.errors[:title]).to include("can't be blank")
    expect(feed.errors[:url]).to include("can't be blank")
  end

  it "url は一意" do
    existing = create(:feed)
    dup = Feed.new(title: "別名", url: existing.url)
    expect(dup).not_to be_valid
    expect(dup.errors[:url]).to include("has already been taken")
  end

  it "削除すると記事も消える" do
    feed = create(:feed)
    create_list(:article, 2, feed: feed)
    expect { feed.destroy! }.to change(Article, :count).by(-2)
  end
end
