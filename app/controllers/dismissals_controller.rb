# 記事を読まずに片付ける「興味なし」と、その取り消し。{Reading} は作らない（抽選もカードも無い）。
# Turbo の要求にはカードの差し替えと未読数だけを返し、JS が無ければ一覧へ戻す
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

  # 未読数はカードを差し替えた後の値。一覧全体は描き直さない（スクロール位置を保つ）
  def respond
    @unread_count = Article.unread.count
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  end
end
