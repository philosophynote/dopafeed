# 購読を管理する入口。取得は既存の Job に委ね、一覧の読み取りと削除だけを担う。
class FeedsController < ApplicationController
  def index
    @feeds = Feed.order(:id)
    @article_counts, @unread_counts = Feed.article_counts
    @unread_count = @unread_counts.values.sum
  end

  def destroy
    Feed.find(params[:id]).destroy!
    redirect_to feeds_path, status: :see_other
  end
end
