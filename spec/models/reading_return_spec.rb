# 記事を読み終えたときの判定（docs/screens/reader.md の受け入れ条件）。完読した行がそのままカードになり、数値の XP は確定しない（ADR 0020）。
# 数字はすべて dopamine.yml から組み立てる
RSpec.describe Reading, "#return!" do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:reset_hour) { settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }
  let(:common) { Dopamine.rarity_names.first }
  let(:rare) { Dopamine.rarity_names.second }

  # 完読 1 本（noon の少し前に判定した）
  def completed_before(time, tier: common)
    create(:reading, tier: tier, opened_at: time - threshold - 1.minute).return!(at: time)
  end

  # 未完 1 本（threshold 未満で判定した）
  def incomplete_before(time)
    create(:reading, tier: common, opened_at: time - threshold + 5.seconds).return!(at: time)
  end

  it "complete_after_seconds + 5 秒で読み終えれば完読でカードになる" do
    reading = create(:reading, tier: common, opened_at: noon)
    reading.return!(at: noon + threshold + 5.seconds)

    expect(reading).to be_completed
    expect(reading.returned_at).to eq(noon + threshold + 5.seconds)
    expect(reading.completed_at).to eq(reading.returned_at)
    expect(Reading.completed).to contain_exactly(reading)
  end

  it "complete_after_seconds ちょうどで読み終えれば完読" do
    reading = create(:reading, tier: common, opened_at: noon)
    reading.return!(at: noon + threshold)
    expect(reading).to be_completed
  end

  it "complete_after_seconds − 10 秒で読み終えれば未完でカードにならず、記事は未読のまま" do
    reading = create(:reading, tier: common, opened_at: noon)
    reading.return!(at: noon + threshold - 10.seconds)

    expect(reading).not_to be_completed
    expect(reading.returned_at).to be_present
    expect(Reading.completed).to be_empty
    expect(Article.unread).to include(reading.article)
  end

  it "希少度は抽選のまま確定する（完読で変わらない）" do
    reading = create(:reading, tier: rare, opened_at: noon)
    reading.return!(at: noon + threshold)

    expect(reading.tier).to eq(rare)
    expect(reading.reload.tier).to eq(rare)
  end

  it "同じ読書日に直前 2 本を連続完読していれば、この完読を含めて 3 本連続" do
    completed_before(noon - 20.minutes)
    completed_before(noon - 10.minutes)
    reading = create(:reading, tier: common, opened_at: noon)
    reading.return!(at: noon + threshold)

    expect(reading.combo_count).to eq(3)
  end

  it "直前が未完読ならコンボは 1 から数え直す" do
    completed_before(noon - 30.minutes)
    completed_before(noon - 20.minutes)
    incomplete_before(noon - 10.minutes)
    reading = create(:reading, tier: common, opened_at: noon)
    reading.return!(at: noon + threshold)

    expect(reading.combo_count).to eq(1)
  end

  it "前日の完読はコンボに数えない（reset_hour で切る）" do
    completed_before(Time.zone.local(2026, 10, 20, reset_hour) - 10.minutes)
    reading = create(:reading, tier: common, opened_at: noon)
    reading.return!(at: noon + threshold)

    expect(reading.combo_count).to eq(1)
  end

  it "判定前の行はコンボを切らない" do
    completed_before(noon - 20.minutes)
    create(:reading, tier: common, opened_at: noon - 10.minutes)
    reading = create(:reading, tier: common, opened_at: noon)
    reading.return!(at: noon + threshold)

    expect(reading.combo_count).to eq(2)
  end

  it "未完の combo_count は 0" do
    completed_before(noon - 20.minutes)
    reading = create(:reading, tier: common, opened_at: noon)
    reading.return!(at: noon + 5.seconds)

    expect(reading.combo_count).to eq(0)
  end

  it "2 回目の判定は何も変えない（冪等）" do
    reading = create(:reading, tier: common, opened_at: noon)
    reading.return!(at: noon + threshold)
    first = reading.attributes

    reading.return!(at: noon + 1.hour)
    expect(reading.reload.attributes).to eq(first)
  end

  it "reopen! は未完の行だけ opened_at を今にして returned_at を消し、tier は使い回す" do
    reading = create(:reading, tier: rare, opened_at: noon)
    reading.return!(at: noon + 5.seconds)
    reading.reopen!(at: noon + 1.hour)

    expect(reading.opened_at).to eq(noon + 1.hour)
    expect(reading.returned_at).to be_nil
    expect(reading.tier).to eq(rare)

    done = create(:reading, tier: common, opened_at: noon)
    done.return!(at: noon + threshold)
    expect { done.reopen!(at: noon + 2.hours) }.not_to change { done.reload.attributes }
  end
end

# goal 本目の完読で宝箱（daily_goals）の行ができる。判定の瞬間に記録し、画面を開いた時には書かない
RSpec.describe Reading, "#return! と今日のゴール" do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:reset_hour) { settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }

  before { (goal_articles - 1).times { create(:reading, :completed, opened_at: noon - 1.hour) } }

  it "goal 本目の完読で achieved_at = 判定の時刻の行ができる" do
    create(:reading, opened_at: noon).return!(at: noon + threshold)

    goal = DailyGoal.find_by(day: ReadingDay.of(noon))
    expect(goal).to be_achieved
    expect(goal.achieved_at).to eq(noon + threshold)
  end

  it "未完では作らない" do
    create(:reading, opened_at: noon).return!(at: noon + threshold - 1.second)
    expect(DailyGoal.count).to eq(0)
  end
end
