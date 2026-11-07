# 朝のダイジェスト（ADR 0013。第一の陣は新着の未読の見出しで代替、タップ先は Main）
RSpec.describe Push::Digest do
  let(:day) { Date.new(2026, 11, 7) }

  def with_push(push)
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(push: push))
  end

  describe "#due?" do
    it "読書日の push.digest_at を過ぎたら真。前は偽。翌日の reset_hour 前（同じ読書日）でも真" do
      with_push(digest_at: "07:30")
      notice = described_class.new(day)

      expect(notice.due?(Time.zone.local(2026, 11, 7, 7, 29))).to be(false)
      expect(notice.due?(Time.zone.local(2026, 11, 7, 7, 30))).to be(true)
      expect(notice.due?(Time.zone.local(2026, 11, 8, 1, 0))).to be(true)
    end

    it "鍵が無ければ常に偽（nao が足すまで送らない）。引用符を忘れた六十進数でも時刻に戻す" do
      with_push({})
      expect(described_class.new(day).due?(Time.zone.local(2026, 11, 7, 12))).to be(false)

      with_push(digest_at: 27_000)
      expect(described_class.new(day).due?(Time.zone.local(2026, 11, 7, 7, 30))).to be(true)

      with_push(digest_at: "7時半")
      expect(described_class.new(day).due?(Time.zone.local(2026, 11, 7, 12))).to be(false)
    end
  end

  describe "#payload" do
    before { with_push(digest_at: "07:30", digest_articles: 2) }

    it "前の回（24 時間前）以降に届いた未読の本数を題に、新しい順に push.digest_articles 本の見出しを本文にする。unread は未読の総数、path は Main" do
      travel_to Time.zone.local(2026, 11, 7, 7, 40)
      old = create(:article, title: "古い未読", published_at: 3.days.ago, created_at: Time.zone.local(2026, 11, 6, 7, 29))
      create(:article, :dismissed, title: "興味なし", created_at: Time.zone.local(2026, 11, 7, 6))
      create(:article, :read, title: "読んだ", created_at: Time.zone.local(2026, 11, 7, 6))
      create(:article, title: "新着 1", published_at: Time.zone.local(2026, 11, 7, 5), created_at: Time.zone.local(2026, 11, 7, 6))
      create(:article, title: "新着 2", published_at: Time.zone.local(2026, 11, 7, 6), created_at: Time.zone.local(2026, 11, 7, 7))
      create(:article, title: "新着 3", published_at: Time.zone.local(2026, 11, 6, 9), created_at: Time.zone.local(2026, 11, 6, 7, 30))
      expect(old).to be_persisted

      expect(described_class.new(day).payload).to eq(
        title: "今日の新着 3 本が届きました", body: "新着 2\n新着 1", path: "/", unread: 4, tag: "digest"
      )
    end

    it "新着が無ければ nil（その回は送らない）" do
      travel_to Time.zone.local(2026, 11, 7, 7, 40)
      create(:article, created_at: Time.zone.local(2026, 11, 5, 12))

      expect(described_class.new(day).payload).to be_nil
    end

    it "push.digest_articles が無ければ見出しは付けず題だけ" do
      with_push(digest_at: "07:30")
      travel_to Time.zone.local(2026, 11, 7, 7, 40)
      create(:article, title: "新着", created_at: Time.zone.local(2026, 11, 7, 7))

      expect(described_class.new(day).payload).to include(title: "今日の新着 1 本が届きました", body: nil)
    end
  end
end
