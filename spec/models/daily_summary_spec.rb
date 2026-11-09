# 読書日 1 日ぶんの数（本数・滞在・ゴールまでの残り）とその日のカード。Main・判定の区切り・DailyGoal が同じ数を見る
RSpec.describe DailySummary do
  let(:settings) { Dopamine.settings }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:reset_hour) { settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }
  let(:today) { ReadingDay.of(noon) }

  it "その日の完読の本数と滞在の合計を数え、他の日と未完は数えない" do
    create(:reading, :completed, opened_at: noon - 1.hour)
    create(:reading, :completed, opened_at: noon - 2.hours)
    create(:reading, :completed, opened_at: noon - 1.day)
    create(:reading, opened_at: noon - 10.minutes, returned_at: noon - 9.minutes)

    summary = DailySummary.new(today)

    expect(summary.count).to eq(2)
    expect(summary.dwell_seconds).to eq(2 * (4 * 60 + 12))
    expect(summary).not_to respond_to(:xp)
  end

  it "cards はその日の完読を開封の順（古い完読が先）で、他の日と未完は入れない" do
    later = create(:reading, :completed, :rare, opened_at: noon - 1.hour)
    earlier = create(:reading, :completed, opened_at: noon - 2.hours)
    create(:reading, :completed, opened_at: noon - 1.day)
    create(:reading, opened_at: noon - 10.minutes, returned_at: noon - 9.minutes)

    expect(DailySummary.new(today).cards).to eq([ earlier, later ])
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

  it "achieved_by? は同じ時刻の完読が並んでも id の順で goal 本目を 1 行に決める" do
    tied = (goal_articles + 1).times.map { create(:reading, :completed, opened_at: noon - 1.hour) }
    summary = DailySummary.new(today)

    expect(tied.map { |reading| summary.achieved_by?(reading) }.count(true)).to eq(1)
    expect(summary.achieved_by?(tied[goal_articles - 1])).to be(true)
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
