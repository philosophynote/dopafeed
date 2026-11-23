class CommentsController < ApplicationController
  before_action :require_comments_settings
  before_action :set_article

  def show
    @except = except
  end

  def create
    @exhausted = false
    candidates = Persona.enabled.where.not(slug: @article.persona_comments.select(:persona_id)).to_a
    if candidates.any?
      if helpers.comments_budget_exhausted?
        @exhausted = true
      else
        request_comments(candidates.sample(Dopamine.settings.dig(:comments, :personas_shown)))
      end
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(@article, :comments_box), partial: "comments/box",
                                                                                           locals: { article: @article, exhausted: @exhausted, except: except })
      end
      format.html { redirect_to article_comments_path(@article, except: params[:except].presence) }
    end
  end

  def retry
    comment = @article.persona_comments.find(params[:persona_comment_id])
    enqueue(comment, reset: true) if comment.failed? && !helpers.comments_budget_exhausted?

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(helpers.dom_id(comment), partial: "comments/card", locals: { comment: comment }) }
      format.html { redirect_to article_comments_path(@article) }
    end
  end

  private

  def require_comments_settings
    head :not_found unless helpers.comments_enabled?
  end

  def except
    params[:except].to_s.split(",")
  end

  # 二度押しで同じ人の枠が重なったら、先に作られた枠に任せる
  def request_comments(personas)
    personas.each do |persona|
      comment = @article.persona_comments.create!(persona_id: persona.slug)
      enqueue(comment)
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end

  def enqueue(comment, reset: false)
    comment.update!(failed_at: nil, error: nil) if reset
    return if Comments::CommentPersonaJob.perform_later(comment)

    # 積めなかったのに書いている途中のまま残すと、走る Job が無いまま待ち続けて押し直せない
    comment.update!(failed_at: Time.current, error: "Job を積めなかった")
  end

  def set_article
    @article = Article.find(params[:article_id])
  end
end
