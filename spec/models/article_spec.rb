RSpec.describe Article, type: :model do
  it "url は http(s) だけ（リンク先になるので javascript: などを通さない）" do
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
    let!(:dismissed) { create(:article, :dismissed) }

    it "unread は完読した記事と興味なしの記事を除く。開いただけの記事は未読のまま（出目は Reading に残る）" do
      expect(Article.unread).to contain_exactly(opened, untouched)
    end

    it "read は完読した記事だけ（興味なしは読んでいない）" do
      expect(Article.read).to contain_exactly(read)
    end
  end

  describe "dismiss! / undismiss!" do
    let(:at) { Time.zone.local(2026, 10, 20, 12) }

    it "dismiss! は時刻を残して未読から外し、undismiss! で未読に戻る" do
      article = create(:article)

      article.dismiss!(at: at)
      expect(article.reload).to be_dismissed
      expect(article.dismissed_at).to eq(at)
      expect(Article.unread).not_to include(article)

      article.undismiss!
      expect(article.reload).not_to be_dismissed
      expect(Article.unread).to include(article)
    end

    it "二度目の dismiss! は最初の時刻を保つ（二重送信で記録を動かさない）" do
      article = create(:article, :dismissed)
      first = article.dismissed_at

      article.dismiss!(at: at)

      expect(article.reload.dismissed_at).to eq(first)
    end

    it "開いたが未完の記事を興味なしにしても、Reading（出目と滞在）は残り XP は付かない" do
      article = create(:article, :opened)

      expect { article.dismiss!(at: at) }.not_to change(Reading, :count)
      expect(article.reading.reload).not_to be_completed
      expect(article.reading.xp).to eq(0)
      expect(Article.unread).not_to include(article)
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

  it "summary_failed は要約が無く失敗の記録がある記事だけ" do
    failed = create(:article, :summary_failed)
    create(:article, :awaiting_summary)
    create(:article, :summary_failed, summary: "・a\n・b\n・c")

    expect(Article.summary_failed).to contain_exactly(failed)
  end

  it "retry_failed_summaries は失敗だけを要約待ちに戻し、戻した件数を返す" do
    failed = create_list(:article, 2, :summary_failed)
    waiting = create(:article, :awaiting_summary)
    summarized = create(:article, :summary_failed, summary: "・a\n・b\n・c")

    expect(Article.retry_failed_summaries).to eq(2)
    expect(Article.awaiting_summary).to contain_exactly(*failed, waiting)
    expect(failed.map { |article| article.reload.summary_error }).to all(be_nil)
    expect(summarized.reload.summary_failed_at).to be_present
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

  describe "next_unread_after" do
    let(:at) { Time.zone.local(2026, 10, 20, 12) }

    it "published_at が古い方の未読を 1 本返し、完読と興味なしは飛ばす" do
      current = create(:article, published_at: at)
      older = create(:article, published_at: at - 1.hour)
      create(:article, :read, published_at: at - 30.minutes)
      create(:article, :dismissed, published_at: at - 15.minutes)
      create(:article, published_at: at + 1.hour)

      expect(Article.next_unread_after(current)).to eq(older)
      expect(Article.next_unread_after(older)).to be_nil
    end

    it "同時刻なら id の小さい方へ進む" do
      first = create(:article, published_at: at)
      second = create(:article, published_at: at)
      expect(Article.next_unread_after(second)).to eq(first)
      expect(Article.next_unread_after(first)).to be_nil
    end

    it "published_at の無い記事は日付のある記事の後に、id の降順で続く" do
      dated = create(:article, published_at: at)
      undated_old = create(:article, published_at: nil)
      undated_new = create(:article, published_at: nil)

      expect(Article.next_unread_after(dated)).to eq(undated_new)
      expect(Article.next_unread_after(undated_new)).to eq(undated_old)
      expect(Article.next_unread_after(undated_old)).to be_nil
    end
  end
end
