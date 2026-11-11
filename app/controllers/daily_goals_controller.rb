class DailyGoalsController < ApplicationController
  def show
    @summary = DailySummary.new
    @next_article = Article.unread.newest_first.first
  end
end
