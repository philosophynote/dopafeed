# 今日のゴール（宝箱）を描く読み取り専用。達成なら開いた宝箱と中身、未達なら閉じた宝箱と残り
class DailyGoalsController < ApplicationController
  def show
    @summary = DailySummary.new
    @goal = DailyGoal.find_by(day: @summary.day)
    # 「もう 1 本だけ」の行き先。入口の一番上のカードと同じ記事
    @next_article = Article.unread.newest_first.first
  end
end
