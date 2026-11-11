module TodayStatus
  extend ActiveSupport::Concern

  private

  def load_today_status
    @cards_count = Reading.card_count
    summary = DailySummary.new
    @today_count = summary.count
    @goal_articles = summary.goal
    @streak_days = ReadingStreak.days
    @combo_count = Combo.new.count
  end
end
