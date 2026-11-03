RSpec.describe Article, type: :model do
  it "url は http(s) だけ（redirect 先になるので javascript: などを通さない）" do
    expect(build(:article, url: "https://example.com/ok")).to be_valid
    expect(build(:article, url: "javascript:alert(1)")).not_to be_valid
    expect(build(:article, url: "ftp://example.com/x")).not_to be_valid
  end

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

  it "[feed_id, guid] は DB で一意（guid nil は複数可）" do
    feed = create(:feed)
    create(:article, feed: feed, guid: "g-1")
    expect { create(:article, feed: feed, guid: "g-1") }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { create(:article, guid: "g-1") }.not_to raise_error
    expect { create_list(:article, 2, feed: feed, guid: nil) }.not_to raise_error
  end

  it "summary が無くても保存できる（要約は Unit 4 の Job が付ける）" do
    expect(build(:article, :unsummarized)).to be_valid
  end

  it "content, guid, liked_at, bookmarked_at は無くてもよい（Unit 3 以降が埋める）" do
    article = build(:article)
    expect(article).to be_valid
    expect(article.content).to be_nil
    expect(article.guid).to be_nil
    expect(article).not_to be_saved
  end

  describe "unread / read" do
    let!(:read) { create(:article, :read) }
    let!(:opened) { create(:article, :opened) }
    let!(:untouched) { create(:article) }

    it "unread は完読した記事を除く。開いただけの記事は未読のまま（出目は Reading に残る）" do
      expect(Article.unread).to contain_exactly(opened, untouched)
    end

    it "read は完読した記事だけ" do
      expect(Article.read).to contain_exactly(read)
    end
  end

  it "awaiting_summary は要約も失敗も無く、本文取得を試した記事だけ（取得に失敗した記事は含む）" do
    waiting = create(:article, :awaiting_summary)
    failed_fetch = create(:article, :awaiting_summary, content_error: "本文を抽出できません")
    create(:article, :awaiting_summary, summary: "・a\n・b\n・c")
    create(:article, :awaiting_summary, summary_failed_at: Time.current, summary_error: "本文が空")
    create(:article, :unsummarized)

    expect(Article.awaiting_summary).to contain_exactly(waiting, failed_fetch)
  end

  it "saved は liked_at か bookmarked_at のある記事" do
    liked = create(:article, :liked)
    bookmarked = create(:article, :bookmarked)
    plain = create(:article)

    expect(Article.saved).to contain_exactly(liked, bookmarked)
    expect(liked).to be_saved
    expect(bookmarked).to be_saved
    expect(plain).not_to be_saved
  end

  it "newest_first は published_at の新しい順" do
    oldest = create(:article, published_at: Time.zone.local(2026, 10, 1, 9))
    newest = create(:article, published_at: Time.zone.local(2026, 10, 3, 9))
    middle = create(:article, published_at: Time.zone.local(2026, 10, 2, 9))

    expect(Article.newest_first.to_a).to eq([ newest, middle, oldest ])
  end

  it "記事を消すと読了も消える" do
    article = create(:article, :read)
    expect { article.destroy! }.to change(Reading, :count).by(-1)
  end
end
