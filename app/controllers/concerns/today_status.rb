module TodayStatus
  extend ActiveSupport::Concern

  private

  def load_today_status
    @total_xp = Reading.completed.sum(:xp) + DailyGoal.bonus_total
    summary = DailySummary.new
    @today_count = summary.count
    @goal_articles = summary.goal
    @streak_days = ReadingStreak.days
    @combo_multiplier = Combo.new.multiplier
  end
end
