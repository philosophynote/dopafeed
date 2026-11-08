# 入口の一覧。未読の記事と、今日の進み（ゴール・ストリーク・累計）を一度に出す読み取り専用。
# 数値はこの画面でしか使わないので、ここで集めてビューに渡す
class MainController < ApplicationController
  def show
    @articles = Article.unread.newest_first.includes(:feed).load
    @unread_count = @articles.size
    @total_xp = Reading.completed.sum(:xp) + DailyGoal.bonus_total
    summary = DailySummary.new
    @today_count = summary.count
    @goal_articles = summary.goal
    @streak_days = ReadingStreak.days
    @combo_multiplier = Combo.new.multiplier
  end
end
