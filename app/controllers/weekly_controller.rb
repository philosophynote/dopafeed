class WeeklyController < ApplicationController
  def show
    @report = WeeklyReport.new
    @unread_count = unread_count
  end
end
