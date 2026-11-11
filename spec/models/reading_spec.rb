RSpec.describe Reading, type: :model do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }

  it "article, opened_at, tier が必須" do
    reading = Reading.new
    expect(reading).not_to be_valid
    expect(reading.errors[:article]).to include("must exist")
    expect(reading.errors[:opened_at]).to include("can't be blank")
    expect(reading.errors[:tier]).to include("is not included in the list")
  end

  it "tier は dopamine.yml の cards.rarities の name だけ" do
    article = create(:article)
    Dopamine.rarity_names.each do |name|
      expect(build(:reading, article: article, tier: name)).to be_valid, "#{name} は有効な tier"
    end

    bogus = build(:reading, article: article, tier: "legendary")
    expect(bogus).not_to be_valid
    expect(bogus.errors[:tier]).to include("is not included in the list")
  end

  it "jackpot? は tier が Dopamine.top_rarity（yml の最後の段）のときだけ" do
    expect(build(:reading, tier: Dopamine.top_rarity[:name])).to be_jackpot
    expect(build(:reading, tier: Dopamine.rarity_names.first)).not_to be_jackpot
  end

  it "1 記事 1 行（同じ記事に 2 行目は作れない）" do
    existing = create(:reading)
    dup = build(:reading, article: existing.article)
    expect(dup).not_to be_valid
    expect(dup.errors[:article_id]).to include("has already been taken")
  end

  it "数値の XP は持たない（完読した行がそのままカード。ADR 0020）" do
    expect(Reading.column_names).not_to include("xp", "combo_multiplier")
  end

  it "card_count は完読した行の数（開いただけ・未完は数えない）" do
    create(:reading, :completed)
    create(:reading, :completed, :jackpot)
    create(:reading)
    create(:reading, opened_at: Time.zone.local(2026, 10, 6, 8), returned_at: Time.zone.local(2026, 10, 6, 8, 0, 5))
    expect(Reading.card_count).to eq(2)
  end

  it "completed? は completed_at の有無" do
    expect(build(:reading, :completed)).to be_completed
    expect(build(:reading)).not_to be_completed
  end

  it "dwell_seconds は読み終えた時刻 − 開いた時刻。判定前なら nil" do
    completed = build(:reading, :completed)
    expect(completed.dwell_seconds).to eq(4 * 60 + 12)
    expect(build(:reading).dwell_seconds).to be_nil
  end

  it "completed_at があるなら returned_at も要る" do
    reading = build(:reading, :completed, returned_at: nil)
    expect(reading).not_to be_valid
    expect(reading.errors[:returned_at]).to include("can't be blank")
  end

  it "completed スコープは completed_at のある行だけ" do
    completed = create(:reading, :completed)
    create(:reading)
    expect(Reading.completed).to contain_exactly(completed)
  end

  it "on(day) は reset_hour 基準の 1 日で completed_at を絞る" do
    day = Date.new(2026, 10, 20)
    just_before = complete(at: Time.zone.local(2026, 10, 20, reset_hour) - 1.minute)
    at_start = complete(at: Time.zone.local(2026, 10, 20, reset_hour))
    last_minute = complete(at: Time.zone.local(2026, 10, 21, reset_hour) - 1.minute)
    next_day_start = complete(at: Time.zone.local(2026, 10, 21, reset_hour))
    opened_only = create(:reading, opened_at: Time.zone.local(2026, 10, 20, reset_hour) + 1.hour)

    expect(Reading.on(day)).to contain_exactly(at_start, last_minute)
    expect(Reading.on(day - 1)).to include(just_before)
    expect(Reading.on(day + 1)).to include(next_day_start), "翌日の reset_hour ちょうどは翌日分（SQL の < で切る）"
    expect(Reading.on(day)).not_to include(opened_only), "completed_at が nil の行は除く"
  end

  def complete(at:)
    create(:reading, :completed, opened_at: at - 1.minute, returned_at: at, completed_at: at)
  end

  describe ".open!" do
    let(:at) { Time.zone.local(2026, 10, 20, 12) }
    let(:rare) { Dopamine.rarity_names.second }

    it "行が無ければ抽選して opened_at を今にして作る" do
      article = create(:article)
      allow(RarityDraw).to receive(:draw).and_return(rare)

      reading = Reading.open!(article, at: at)

      expect(reading).to be_persisted
      expect(reading.tier).to eq(rare)
      expect(reading.opened_at).to eq(at)
    end

    it "未完の行があれば再抽選せず開き直す" do
      reading = create(:reading, tier: rare, opened_at: at - 1.hour, returned_at: at - 1.hour + 5.seconds)
      expect(RarityDraw).not_to receive(:draw)

      expect(Reading.open!(reading.article, at: at)).to eq(reading)
      expect(reading.reload.opened_at).to eq(at)
      expect(reading.returned_at).to be_nil
    end

    it "完読済みの行は変えない" do
      reading = create(:reading, :completed)
      before = reading.attributes
      expect(Reading.open!(reading.article, at: at).attributes).to eq(before)
    end

    it "同時に作られて一意制約で落ちたら、先に入った行を返す" do
      article = create(:article)
      existing = create(:reading, article: article, tier: rare, opened_at: at - 1.minute)
      ghost = Reading.new(article: article)
      allow(Reading).to receive(:find_or_initialize_by).and_return(ghost)
      allow(ghost).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new("二重タップ"))

      expect(Reading.open!(article, at: at)).to eq(existing)
    end
  end

  describe "#start!" do
    let(:at) { Time.zone.local(2026, 10, 20, 12) }

    it "判定前なら opened_at を記事を開いた時刻にする（カードを眺めていた時間は滞在に入れない）" do
      reading = create(:reading, opened_at: at - 10.minutes)

      expect(reading.start!(at: at)).to eq(reading)
      expect(reading.reload.opened_at).to eq(at)
      expect(reading.returned_at).to be_nil
    end

    it "判定済みなら未完でも何もしない（区切りの滞在を書き換えない）" do
      incomplete = create(:reading, opened_at: at - 1.minute, returned_at: at - 50.seconds)
      completed = create(:reading, :completed)

      expect { incomplete.start!(at: at) }.not_to(change { incomplete.reload.attributes })
      expect { completed.start!(at: at) }.not_to(change { completed.reload.attributes })
    end
  end
end
