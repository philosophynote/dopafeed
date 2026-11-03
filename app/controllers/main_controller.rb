# 入口の一覧。未読の記事と、今日の進み（ゴール・ストリーク・累計）を一度に出す読み取り専用。
# 数値はこの画面でしか使わないので、ここで集めてビューに渡す
class MainController < ApplicationController
  def show
    @articles = Article.unread.newest_first.includes(:feed).load
    @unread_count = @articles.size
    @read_count = Reading.completed.count
    @total_xp = Reading.completed.sum(:xp)
    @today_count = Reading.on(ReadingDay.of).count
    @goal_articles = Dopamine.settings.dig(:daily_goal, :articles)
    @streak_days = ReadingStreak.days
    @combo_multiplier = Combo.new.multiplier
    @pending_reading = Reading.where(returned_at: nil).order(opened_at: :desc).includes(:article).first
  end
end
