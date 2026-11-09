# 記事を「あとで読む」に取り置く保存と、その取り消し。{DismissalsController} と同じく {Reading} は作らず（抽選もカードも無い）、
# 違いは捨てずに取り置くこと（{Article.bookmarked} に入る）。Turbo の要求には行の差し替えと数だけを返し、JS が無ければ一覧へ戻す。
# 取り置いた記事の一覧から外したときは from=saved が付き、行の差し替え先と戻り先がその一覧になる
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

  # 一覧全体は描き直さない（スクロール位置を保つ）
  def respond
    @unread_count = Article.unread.count
    @saved_count = Article.bookmarked.count if @from_saved
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @from_saved ? saved_path : root_path }
    end
  end
end
