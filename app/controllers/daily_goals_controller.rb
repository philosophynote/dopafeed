class DailyGoalsController < ApplicationController
  def show
    @summary = DailySummary.new
    @next_article = Article.unread.newest_first.first
    # HEAD は描かないので、開いたことにしない
    @finale = !request.head? && @summary.reached? && DailyGoal.find_by(day: @summary.day)&.open_chest!
  end
end
