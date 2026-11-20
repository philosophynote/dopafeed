class CommentsController < ApplicationController
  before_action :require_comments_settings
  before_action :set_article

  def show
    @except = params[:except].to_s.split(",")
  end

  def create
    @exhausted = false
    unless @article.persona_comments.exists?
      @exhausted = helpers.comments_budget_exhausted?
      request_comments unless @exhausted
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(@article, :comments_box), partial: "comments/box",
                                                                                           locals: { article: @article, exhausted: @exhausted })
      end
      format.html { redirect_to article_comments_path(@article) }
    end
  end

  private

  def require_comments_settings
    head :not_found unless helpers.comments_enabled?
  end

  def request_comments
    @article.update!(comments_requested_at: Time.current, comments_failed_at: nil, comments_error: nil)
    Comments::CommentArticleJob.perform_later(@article)
  end

  def set_article
    @article = Article.find(params[:article_id])
  end
end
