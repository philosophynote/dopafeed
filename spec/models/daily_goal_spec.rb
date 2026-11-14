RSpec.describe DailyGoal, type: :model do
  it "day が必須" do
    goal = DailyGoal.new
    expect(goal).not_to be_valid
    expect(goal.errors[:day]).to include("can't be blank")
  end

  it "同じ日に 2 行は作れない（宝箱は 1 日 1 回）" do
    existing = create(:daily_goal)
    dup = build(:daily_goal, day: existing.day)
    expect(dup).not_to be_valid
    expect(dup.errors[:day]).to include("has already been taken")
  end

  it "achieved? は achieved_at の有無" do
    expect(build(:daily_goal, :achieved)).to be_achieved
    expect(build(:daily_goal)).not_to be_achieved
  end

  it "ボーナス XP の列は持たない（宝箱の中身は今日のカード。ADR 0020）" do
    expect(DailyGoal.column_names).not_to include("bonus_xp")
  end
end

RSpec.describe DailyGoal, ".achieve_if_reached!" do
  let(:settings) { Dopamine.settings }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:reset_hour) { settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }
  let(:today) { ReadingDay.of(noon) }

  def complete(count, at: noon - 1.hour)
    count.times { create(:reading, :completed, opened_at: at) }
  end

  it "完読が goal に満たなければ行を作らず nil" do
    complete(goal_articles - 1)
    expect(DailyGoal.achieve_if_reached!(at: noon)).to be_nil
    expect(DailyGoal.count).to eq(0)
  end

  it "goal 本目で achieved_at = at の行を作る" do
    complete(goal_articles)
    goal = DailyGoal.achieve_if_reached!(at: noon)

    expect(goal.day).to eq(today)
    expect(goal.achieved_at).to eq(noon)
  end

  it "2 回呼んでも行は 1 つ（1 日 1 回）" do
    complete(goal_articles + 1)

    first = DailyGoal.achieve_if_reached!(at: noon)
    second = DailyGoal.achieve_if_reached!(at: noon + 1.hour)

    expect(second).to eq(first)
    expect(DailyGoal.count).to eq(1)
  end

  it "同時に 2 本届いて後の 1 本が一意性の検証で落ちたら先の行を使う" do
    complete(goal_articles)
    existing = create(:daily_goal, :achieved, day: today)
    # 1 回目の find_by では行がまだ見えず、落ちた後の find_by! では見える体にする
    allow(DailyGoal).to receive(:find_by).and_return(nil, existing)

    expect(DailyGoal.achieve_if_reached!(at: noon)).to eq(existing)
    expect(DailyGoal.count).to eq(1)
  end

  it "検証をすり抜けて DB の一意制約で落ちても先の行を使う" do
    complete(goal_articles)
    existing = create(:daily_goal, :achieved, day: today)
    # 1 回目の find_by では行がまだ見えず、落ちた後の find_by! では見える体にする
    allow(DailyGoal).to receive(:find_by).and_return(nil, existing)
    allow(DailyGoal).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

    expect(DailyGoal.achieve_if_reached!(at: noon)).to eq(existing)
  end

  it "reset_hour の手前（3:59）の完読は前日の行、ちょうど（4:00）は当日の行" do
    before_reset = Time.zone.local(2026, 10, 21, reset_hour) - 1.minute
    complete(goal_articles, at: before_reset - 10.minutes)
    expect(DailyGoal.achieve_if_reached!(at: before_reset).day).to eq(today)

    at_reset = Time.zone.local(2026, 10, 21, reset_hour)
    complete(goal_articles, at: at_reset)
    expect(DailyGoal.achieve_if_reached!(at: at_reset + 5.minutes).day).to eq(today + 1)
  end
end

RSpec.describe DailyGoal, "#open_chest!" do
  it "達成した日に初めて開いたときだけ true を返して時刻を残し、2 度目からは false で時刻を動かさない" do
    goal = create(:daily_goal, :achieved)
    at = goal.achieved_at + 1.hour

    expect(goal.open_chest!(at: at)).to be(true)
    expect(goal.reload.chest_opened_at).to be_within(1.second).of(at)
    expect(goal.open_chest!(at: at + 1.hour)).to be(false)
    expect(goal.reload.chest_opened_at).to be_within(1.second).of(at)
  end

  it "別の読み込みで先に開かれていたら、古い行から開いても false で上書きしない（2 つの画面で同時に開いてもフィナーレは 1 回）" do
    goal = create(:daily_goal, :achieved)
    stale = DailyGoal.find(goal.id)

    expect(goal.open_chest!).to be(true)
    expect(stale.open_chest!).to be(false)
  end

  it "未達の行は開けない" do
    goal = create(:daily_goal)
    expect(goal.open_chest!).to be(false)
    expect(goal.reload.chest_opened_at).to be_nil
  end
end
