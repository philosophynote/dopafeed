# 入口の一覧。未読の記事と、今日の進み（ゴール・ストリーク・図鑑の枚数・連続）を一度に出す読み取り専用。
# 数値はこの画面でしか使わないので、ここで集めてビューに渡す
class MainController < ApplicationController
  def show
    @articles = Article.unread.newest_first.includes(:feed).load
    @unread_count = @articles.size
    @cards_count = Reading.card_count
    summary = DailySummary.new
    @today_count = summary.count
    @goal_articles = summary.goal
    @streak_days = ReadingStreak.days
    @combo_count = Combo.new.count
  end
end
