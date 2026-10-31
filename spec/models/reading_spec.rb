RSpec.describe Reading, type: :model do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }

  it "article, opened_at, tier が必須" do
    reading = Reading.new
    expect(reading).not_to be_valid
    expect(reading.errors[:article]).to include("must exist")
    expect(reading.errors[:opened_at]).to include("can't be blank")
    expect(reading.errors[:tier]).to include("is not included in the list")
  end

  it "tier は dopamine.yml の xp.tiers の name だけ" do
    article = create(:article)
    Dopamine.tier_names.each do |name|
      expect(build(:reading, article: article, tier: name)).to be_valid, "#{name} は有効な tier"
    end

    bogus = build(:reading, article: article, tier: "legendary")
    expect(bogus).not_to be_valid
    expect(bogus.errors[:tier]).to include("is not included in the list")
  end

  it "1 記事 1 行（同じ記事に 2 行目は作れない）" do
    existing = create(:reading)
    dup = build(:reading, article: existing.article)
    expect(dup).not_to be_valid
    expect(dup.errors[:article_id]).to include("has already been taken")
  end

  it "xp は 0 以上の整数" do
    reading = build(:reading, :completed)
    reading.xp = -1
    expect(reading).not_to be_valid
    reading.xp = 0
    expect(reading).to be_valid
  end

  it "開いただけなら xp は 0、combo_multiplier は nil" do
    reading = create(:reading)
    expect(reading.xp).to eq(0)
    expect(reading.combo_multiplier).to be_nil
  end

  it "completed? は completed_at の有無" do
    expect(build(:reading, :completed)).to be_completed
    expect(build(:reading)).not_to be_completed
  end

  it "dwell_seconds は戻った時刻 − 開いた時刻。戻っていなければ nil" do
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

  # 完読した Reading を 1 行作る（開いた時刻は 1 分前）
  #
  # @param at [ActiveSupport::TimeWithZone] 完読した時刻
  # @return [Reading]
  def complete(at:)
    create(:reading, :completed, opened_at: at - 1.minute, returned_at: at, completed_at: at)
  end
end
