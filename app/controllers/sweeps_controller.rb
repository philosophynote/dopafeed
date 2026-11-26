class SweepsController < ApplicationController
  helper_method :flow?

  def create
    @articles = Article.transaction do
      articles = Article.unread.where(id: article_ids).includes(:feed).to_a
      Article.where(id: articles.map(&:id)).update_all(dismissed_at: Time.current, updated_at: Time.current)
      articles + dismissed_since_rendered.where.not(id: articles.map(&:id)).includes(:feed).to_a
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

  def flow?
    params[:flow].present?
  end

  def article_ids
    Array(params[:article_ids])
  end

  # 初めの片付けが書き込めたのに応答が届かず押し直すと、未読で絞った分は空になり、行も「元に戻す」も戻らない。
  # 送られてくるのは画面で見えていた行だけなので、表示の後に消えた記事は届かなかった片付けの分とみなす
  def dismissed_since_rendered
    rendered_at = Time.zone.iso8601(params[:rendered_at].to_s)
    Article.where(id: article_ids, liked_at: nil, bookmarked_at: nil, dismissed_at: rendered_at..)
           .where.not(id: Reading.completed.select(:article_id))
  rescue ArgumentError
    Article.none
  end

  def respond
    @unread_count = Article.unread.count
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  end
end
