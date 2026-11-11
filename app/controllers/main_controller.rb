class MainController < ApplicationController
  include TodayStatus

  def show
    @articles = Article.unread.newest_first.includes(:feed).load
    @unread_count = @articles.size
    load_today_status
  end
end
