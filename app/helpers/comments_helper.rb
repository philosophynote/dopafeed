module CommentsHelper
  # 鍵が揃うまで、または有効な人物がいない間は、押しても Job が失敗するだけなので、入口ごと出さない。
  def comments_enabled?
    settings = Dopamine.settings[:comments].to_h
    %i[personas_shown model max_tokens timeout_seconds].all? { |key| settings[key].present? } && Persona.enabled.exists?
  end

  def comments_budget_exhausted?
    Claude::Budget.new.exhausted?
  end

  def comments_state(article, exhausted: false)
    return :ready if article.persona_comments.by_enabled_personas.exists?
    return :exhausted if exhausted
    # 走っている Job が最後の 1 回を使っても、出来上がりを待つ間は上限にしない
    return :pending if article.comments_requested_at.present? && article.comments_failed_at.blank?
    # 知らせを取りこぼしても取り直しで上限を出す。押せない日に前の失敗の「もう一度」は出さない
    return :exhausted if comments_budget_exhausted?
    return :failed if article.comments_failed_at.present?

    :closed
  end

  # 人物を外して残りが足りなくなっても、空や欠けた組を出さないよう有効な全員から選び直す。
  def shown_persona_comments(article, except: [])
    count = Dopamine.settings.dig(:comments, :personas_shown)
    saved = article.persona_comments.by_enabled_personas.includes(:persona).to_a
    rest = saved.reject { |comment| comment.persona_id.in?(except) }
    (rest.size >= count ? rest : saved).sample(count)
  end
end
