# 購読の一覧・登録・削除の入口。記事の取り込みは既存の Job に委ねる。
class FeedsController < ApplicationController
  before_action :set_back_path, only: %i[new create]

  def new
  end

  def create
    @url = params.expect(feed: [ :url ])[:url]
    @result = FeedRegistration.call(@url)
    render :new, status: @result.feed ? :ok : :unprocessable_content
  end

  def index
    @feeds = Feed.order(:id)
    @article_counts, @unread_counts = Feed.article_counts
    @unread_count = @unread_counts.values.sum
  end

  def destroy
    Feed.find(params[:id]).destroy!
    redirect_to feeds_path, status: :see_other
  end

  private

  def set_back_path
    @back_path = params[:from] == "main" ? root_path : feeds_path
  end
end
