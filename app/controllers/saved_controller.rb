class SavedController < ApplicationController
  def show
    @articles = Article.bookmarked.includes(:feed, :reading).load
    @unread_count = Article.unread.count
  end
end
