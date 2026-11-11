class DismissalsController < ApplicationController
  before_action :set_article

  def create
    @article.dismiss!
    respond
  end

  def destroy
    @article.undismiss!
    respond
  end

  private

  def set_article
    @article = Article.includes(:feed).find(params[:article_id])
  end

  # 一覧全体を描き直すとスクロール位置が失われる。
  def respond
    @unread_count = Article.unread.count
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  end
end
