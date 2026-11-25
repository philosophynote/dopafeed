class SweepsController < ApplicationController
  def create
    @articles = Article.transaction do
      articles = Article.unread.where(id: article_ids).includes(:feed).to_a
      Article.where(id: articles.map(&:id)).update_all(dismissed_at: Time.current, updated_at: Time.current)
      articles
    end
    respond
  end

  def destroy
    Article.where(id: article_ids).update_all(dismissed_at: nil, updated_at: Time.current)
    @articles = Article.where(id: article_ids).includes(:feed)
    @unread_ids = Article.unread.where(id: article_ids).ids.to_set
    respond
  end

  private

  def article_ids
    Array(params[:article_ids])
  end

  def respond
    @unread_count = Article.unread.count
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  end
end
