# 記事を「あとで読む」に取り置く保存と、その取り消し。{DismissalsController} と同じく {Reading} は作らず（抽選も XP も無い）、
# 違いは記事が消えずに Saved に移ること。Turbo の要求には行の差し替えと未読数だけを返し、JS が無ければ一覧へ戻す
class BookmarksController < ApplicationController
  before_action :set_article

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

  # 一覧全体は描き直さない（スクロール位置を保つ）
  def respond
    @unread_count = Article.unread.count
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  end
end
