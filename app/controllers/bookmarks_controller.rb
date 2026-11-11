class BookmarksController < ApplicationController
  before_action :set_article
  before_action { @from_saved = params[:from] == "saved" }

  def create
    @article.bookmark!
    respond
  end

  def destroy
    @article.unbookmark!
    respond
  end

  private

  def set_article
    @article = Article.includes(:feed).find(params[:article_id])
  end

  # 一覧全体を描き直すとスクロール位置が失われる。
  def respond
    @unread_count = Article.unread.count
    @saved_count = Article.bookmarked.count if @from_saved
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @from_saved ? saved_path : root_path }
    end
  end
end
