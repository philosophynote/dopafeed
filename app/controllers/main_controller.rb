# 入口の一覧。未読の記事と、今日の進み（ゴール・ストリーク・累計）を一度に出す。
# 数値はこの画面でしか使わないので、ここで集めてビューに渡す。読むだけで、書くのは別のコントローラ
class MainController < ApplicationController
  def show
    @articles = Article.unread.newest_first.includes(:feed)
    @unread_count = Article.unread.count
    @read_count = Reading.completed.count
    @total_xp = Reading.sum(:xp)
    @today_count = Reading.on(ReadingDay.of).count
    @goal_articles = Dopamine.settings.dig(:daily_goal, :articles)
    @streak_days = ReadingStreak.days
  end
end
