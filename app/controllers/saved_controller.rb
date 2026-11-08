# 取り置いた記事の一覧。読み取り専用で、取り置き・取り消しは {BookmarksController} が書く
class SavedController < ApplicationController
  def show
    @articles = Article.bookmarked.includes(:feed, :reading).load
    @unread_count = Article.unread.count
  end
end
