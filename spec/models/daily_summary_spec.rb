# 読書日 1 日ぶんの数（本数・滞在・XP・ゴールまでの残り）。Main・判定の区切り・DailyGoal が同じ数を見る
RSpec.describe DailySummary do
  let(:settings) { Dopamine.settings }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:reset_hour) { settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }
  let(:today) { ReadingDay.of(noon) }

  it "その日の完読の本数・滞在の合計・XP の合計を数え、他の日と未完は数えない" do
    create(:reading, :completed, opened_at: noon - 1.hour, xp: 30)
    create(:reading, :completed, opened_at: noon - 2.hours, xp: 12)
    create(:reading, :completed, opened_at: noon - 1.day, xp: 100)
    create(:reading, opened_at: noon - 10.minutes, returned_at: noon - 9.minutes)

    summary = DailySummary.new(today)

    expect(summary.count).to eq(2)
    expect(summary.dwell_seconds).to eq(2 * (4 * 60 + 12))
    expect(summary.xp).to eq(42)
  end

  it "ゴールまでの残りと到達。超えても残りは 0" do
    expect(DailySummary.new(today).remaining).to eq(goal_articles)
    expect(DailySummary.new(today)).not_to be_reached

    (goal_articles + 1).times { create(:reading, :completed, opened_at: noon - 1.hour) }
    summary = DailySummary.new(today)
    expect(summary.remaining).to eq(0)
    expect(summary).to be_reached
    expect(summary.goal).to eq(goal_articles)
  end

  it "achieved_by? はその日のちょうど goal 本目の完読にだけ真。それ以降・未完・他の日は偽" do
    readings = (goal_articles + 1).times.map { |i| create(:reading, :completed, opened_at: noon - 3.hours + i.minutes) }
    incomplete = create(:reading, opened_at: noon, returned_at: noon + 1.second)
    yesterday = create(:reading, :completed, opened_at: noon - 1.day)
    summary = DailySummary.new(today)

    expect(summary.achieved_by?(readings[goal_articles - 1])).to be(true)
    expect(summary.achieved_by?(readings[goal_articles - 2])).to be(false)
    expect(summary.achieved_by?(readings[goal_articles])).to be(false)
    expect(summary.achieved_by?(incomplete)).to be(false)
    expect(summary.achieved_by?(yesterday)).to be(false)
  end

  it "ストリークはその日を今日として数える" do
    create(:reading, :completed, opened_at: noon - 1.day)
    create(:reading, :completed, opened_at: noon)

    expect(DailySummary.new(today).streak_days).to eq(2)
  end

  it "既定の日は今の読書日" do
    travel_to(noon) { expect(DailySummary.new.day).to eq(today) }
  end
end
