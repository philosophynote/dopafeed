class WeeklyController < ApplicationController
  def show
    @report = WeeklyReport.new
    @comment = WeeklyComment.for_week(@report.start_day - WeeklyReport::DAYS)
    @unread_count = unread_count
  end
end
