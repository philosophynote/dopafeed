class DailyGoalsController < ApplicationController
  def show
    @summary = DailySummary.new
    @goal = DailyGoal.find_by(day: @summary.day)
    @next_article = Article.unread.newest_first.first
  end
end
