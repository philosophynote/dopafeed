require "test_helper"

class DailyGoalTest < ActiveSupport::TestCase
  test "day が必須" do
    goal = DailyGoal.new
    assert_not goal.valid?
    assert_includes goal.errors[:day], "can't be blank"
  end

  test "同じ日に 2 行は作れない（宝箱は 1 日 1 回）" do
    dup = DailyGoal.new(day: daily_goals(:achieved_oct_5).day)
    assert_not dup.valid?
    assert_includes dup.errors[:day], "has already been taken"
  end

  test "achieved? は achieved_at の有無" do
    assert daily_goals(:achieved_oct_5).achieved?
    assert_not DailyGoal.new(day: Date.new(2026, 10, 6)).achieved?
  end

  test "bonus_xp の既定は 0（鍵 daily_goal.bonus_xp が入るまで加算しない）" do
    assert_equal 0, DailyGoal.create!(day: Date.new(2026, 10, 7)).bonus_xp
  end
end
