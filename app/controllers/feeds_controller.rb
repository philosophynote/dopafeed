# 購読の一覧・登録・名前の変更・削除の入口。記事の取り込みは既存の Job に委ねる。
class FeedsController < ApplicationController
  before_action :set_back_path, only: %i[new create]
  before_action :set_feed, only: %i[edit update destroy]

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

  def edit
  end

  # 行ごと差し替えるのは、削除の確認文も名前を含むため
  def update
    unless @feed.update(params.expect(feed: [ :title ]))
      return render :edit, status: :unprocessable_content
    end

    respond_to do |format|
      format.turbo_stream do
        article_counts, unread_counts = Feed.article_counts(@feed.articles)
        render turbo_stream: turbo_stream.replace(@feed, partial: "feeds/feed",
          locals: { feed: @feed, article_count: article_counts.fetch(@feed.id, 0), unread_count: unread_counts.fetch(@feed.id, 0) })
      end
      format.html { redirect_to feeds_path, status: :see_other }
    end
  end

  def destroy
    @feed.destroy!
    redirect_to feeds_path, status: :see_other
  end

  private

  def set_feed
    @feed = Feed.find(params[:id])
  end

  def set_back_path
    @back_path = params[:from] == "main" ? root_path : feeds_path
  end
end
