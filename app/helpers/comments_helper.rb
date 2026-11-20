module CommentsHelper
  # 鍵が揃うまでは押しても Job が設定の欠けで落ちるだけなので、入口ごと出さない。
  def comments_enabled?
    settings = Dopamine.settings[:comments].to_h
    %i[personas_shown model max_tokens timeout_seconds].all? { |key| settings[key].present? }
  end

  def comments_budget_exhausted?
    Claude::Budget.new.exhausted?
  end

  def comments_state(article, exhausted: false)
    return :ready if article.persona_comments.any?
    return :exhausted if exhausted
    return :failed if article.comments_failed_at.present?
    return :pending if article.comments_requested_at.present?
    # Job の中で切れた知らせを取りこぼしても、取り直したときに上限を出す
    return :exhausted if comments_budget_exhausted?

    :closed
  end

  # 人物を減らして残りが足りなくなっても、空や欠けた組を出さないよう全員から選び直す。
  def shown_persona_comments(article, except: [])
    count = Dopamine.settings.dig(:comments, :personas_shown)
    saved = article.persona_comments.select(&:persona)
    rest = saved.reject { |comment| comment.persona_id.in?(except) }
    (rest.size >= count ? rest : saved).sample(count)
  end
end
