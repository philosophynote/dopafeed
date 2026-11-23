class CommentsController < ApplicationController
  before_action :require_comments_settings
  before_action :set_article

  def show; end

  def create
    requested = []
    # SQLite の書き込みトランザクションは 1 本ずつ走るので、二つのタブから同時に押しても組を選ぶのは片方ずつ
    PersonaComment.transaction do
      # 押したときの組が記録した組とも今描く組とも違えば、再送か別のタブで先に替わった後なので、もう一組は作らない。
      # 組を記録する前の記事は、押したときの組と比べる記録が無いのでそのまま受ける
      recorded = PersonaComment.recorded_lineup(@article)
      next if recorded.any? && [ recorded, PersonaComment.lineup(@article).map(&:persona_id) ].none? { |lineup| lineup.sort == except.sort }

      requested = choose_lineup
    end
    # Job は行を書き終えてから積む。トランザクションの中で積むと、走った Job がまだ無い行を探す
    requested.each { |comment| enqueue(comment) }

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(@article, :comments_box), partial: "comments/box",
                                                                                           locals: { article: @article })
      end
      format.html { redirect_to article_comments_path(@article) }
    end
  end

  def retry
    comment = @article.persona_comments.find(params[:persona_comment_id])
    # 外した人は欄に出さないので、頼み直して上限を使わない
    if comment.persona.enabled? && !helpers.comments_budget_exhausted?
      # 二度押しで 2 本積むと、1 本目が再試行を待つ間に 2 本目が同じ人に払うので、戻すのは失敗を見た 1 回だけ
      reset = comment.with_lock { comment.failed? && comment.update!(failed_at: nil, error: nil, updated_at: Time.current) }
    end
    # 応答でカードを返すと、先に終わった Job の失敗のカードを後から届いた応答が上書きしうる。
    # 同じ購読に Job より先に送れば、届く順が書いた順になる
    broadcast_card(comment)
    enqueue(comment) if reset

    respond_to do |format|
      format.turbo_stream { head :no_content }
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

  # 上限で組み替える人もいなければ、今の組を残して上限を出す。押すたびに同じ組とボタンが出ると押し続けてしまう
  def choose_lineup
    candidates = Persona.enabled.where.not(slug: @article.persona_comments.select(:persona_id)).to_a
    # 残りの回数を超えて枠を作ると、上限で失敗すると分かっている枠が並ぶ
    count = [ Dopamine.settings.dig(:comments, :personas_shown), helpers.comments_budget_remaining ].min
    requested = candidates.sample(count).map { |persona| @article.persona_comments.create!(persona_id: persona.slug) }

    saved = @article.persona_comments.by_enabled_personas.includes(:persona).to_a
    return [] if candidates.any? && requested.empty? && saved.all? { |comment| comment.persona_id.in?(except) }

    PersonaComment.where(id: PersonaComment.pick(saved, except:).map(&:id)).update_all(shown_at: Time.current)
    requested
  end

  def enqueue(comment)
    return if Comments::CommentPersonaJob.perform_later(comment)

    mark_unqueued(comment)
  rescue StandardError => e
    # SolidQueue::Job::EnqueueError は ActiveJob::EnqueueError ではないので perform_later が false にせず上がってくる。
    # 上げると残りの人を積まずに終わり、積めなかった人も書いている途中のまま待ち続ける
    Rails.logger.warn("[comments] enqueue failed for persona_comment #{comment.id}: #{e.class.name}")
    mark_unqueued(comment)
  end

  # 積めなかったのに書いている途中のまま残すと、走る Job が無いまま待ち続けて押し直せない
  def mark_unqueued(comment)
    comment.update!(failed_at: Time.current, error: "Job を積めなかった")
    broadcast_card(comment)
  end

  # カードの知らせは欄を早く替えるためのもので、配れなくても行の状態と Job は進める。
  # 上げると、書いている途中に戻した行が Job を積まれないまま残る
  def broadcast_card(comment)
    Comments::CommentPersonaJob.broadcast(comment)
  rescue StandardError => e
    Rails.logger.warn("[comments] card broadcast failed for persona_comment #{comment.id}: #{e.class.name}")
  end

  def set_article
    @article = Article.find(params[:article_id])
  end
end
