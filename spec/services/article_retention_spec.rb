RSpec.describe ArticleRetention do
  let(:now) { Time.zone.local(2026, 11, 20, 12) }

  before { allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(retention: { dismissed_days: 1, unread_days: 3 })) }

  def purge
    described_class.call(now: now)
  end

  describe "削除済みの記事" do
    it "削除から 1 日経てば消え、23 時間なら残る" do
      expired = create(:article, dismissed_at: now - 1.day)
      fresh = create(:article, dismissed_at: now - 23.hours)

      expect(purge.dismissed).to eq(1)
      expect(Article.exists?(expired.id)).to be(false)
      expect(Article.exists?(fresh.id)).to be(true)
    end

    it "取得から 3 日経っていなくても、削除から 1 日経てば消える" do
      article = create(:article, created_at: now - 2.days, dismissed_at: now - 1.day)
      purge
      expect(Article.exists?(article.id)).to be(false)
    end

    it "保存・いいねが付いていれば日数を過ぎても残る" do
      bookmarked = create(:article, :bookmarked, dismissed_at: now - 5.days)
      liked = create(:article, :liked, dismissed_at: now - 5.days)

      expect(purge.dismissed).to eq(0)
      expect(Article.where(id: [ bookmarked.id, liked.id ]).count).to eq(2)
    end

    it "削除した後に Reader で読み終えた記事（図鑑のカード）は残る" do
      article = create(:article, :read, dismissed_at: now - 5.days)
      purge
      expect(Article.exists?(article.id)).to be(true)
    end
  end

  describe "未読の記事" do
    it "取得から 3 日経てば消え、3 日に満たなければ残る（公開日時は見ない）" do
      expired = create(:article, created_at: now - 3.days, published_at: now - 1.hour)
      fresh = create(:article, created_at: now - 3.days + 1.minute, published_at: now - 30.days)

      expect(purge.unread).to eq(1)
      expect(Article.exists?(expired.id)).to be(false)
      expect(Article.exists?(fresh.id)).to be(true)
    end

    it "開いたが未完の記事は、未完の Reading ごと消える" do
      article = create(:article, :opened, created_at: now - 4.days)
      reading = article.reading

      purge
      expect(Article.exists?(article.id)).to be(false)
      expect(Reading.exists?(reading.id)).to be(false)
    end

    it "保存・いいね・完読の記事は日数を過ぎても残る" do
      kept = [
        create(:article, :bookmarked, created_at: now - 10.days),
        create(:article, :liked, created_at: now - 10.days),
        create(:article, :read, created_at: now - 10.days)
      ]

      expect(purge.unread).to eq(0)
      expect(Article.where(id: kept.map(&:id)).count).to eq(3)
    end
  end

  describe "消したときの記録" do
    it "判定も消え、消した記事の目印が理由つきで 1 行ずつ残る" do
      dismissed = create(:article, guid: "g-1", dismissed_at: now - 2.days)
      unread = create(:article, created_at: now - 4.days)
      create(:article_judgment, article: dismissed)

      purge

      expect(ArticleJudgment.count).to eq(0)
      expect(PurgedArticle.pluck(:feed_id, :guid, :url, :reason)).to contain_exactly(
        [ dismissed.feed_id, "g-1", dismissed.url, "dismissed" ],
        [ unread.feed_id, unread.guid, unread.url, "unread" ]
      )
      expect(PurgedArticle.pluck(:purged_at).uniq).to eq([ now ])
    end

    it "完読の数・その日のゴール・連続日数は変わらない" do
      read = create(:article, :read, created_at: now - 10.days)
      create(:article, :opened, created_at: now - 10.days)
      day = ReadingDay.of(read.reading.completed_at)

      expect { purge }.not_to change { [ Reading.card_count, DailySummary.new(day).count, ReadingStreak.days(today: day) ] }
    end

    it "続けて 2 回回しても目印は増えず、2 回目は何も消さない" do
      create(:article, created_at: now - 4.days)
      purge

      result = nil
      expect { result = purge }.not_to change(PurgedArticle, :count)
      expect(result.to_h).to eq(dismissed: 0, unread: 0)
    end

    it "購読を消すと、そのフィードの目印も消える" do
      article = create(:article, created_at: now - 4.days)
      purge

      expect { article.feed.destroy! }.to change(PurgedArticle, :count).from(1).to(0)
    end
  end

  describe "dopamine.yml に日数が無いとき" do
    it "その区分は消さない（戻せない操作なので、鍵が無ければ安全側に倒す）" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(retention: { unread_days: 3 }))
      dismissed = create(:article, dismissed_at: now - 30.days)
      unread = create(:article, created_at: now - 4.days)

      expect(purge.to_h).to eq(dismissed: 0, unread: 1)
      expect(Article.exists?(dismissed.id)).to be(true)
      expect(Article.exists?(unread.id)).to be(false)
    end

    it "retention ごと無ければ何も消さない" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.except(:retention))
      create(:article, dismissed_at: now - 30.days, created_at: now - 30.days)
      create(:article, created_at: now - 30.days)

      expect { purge }.not_to change(Article, :count)
    end
  end
end
