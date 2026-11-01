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

  it "bonus_xp の既定は 0（鍵 daily_goal.bonus_xp が入るまで加算しない）" do
    expect(create(:daily_goal).bonus_xp).to eq(0)
  end
end
