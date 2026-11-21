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
    # 走っている Job が最後の 1 回を使っても、出来上がりを待つ間は上限にしない
    return :pending if article.comments_requested_at.present? && article.comments_failed_at.blank?
    # 知らせを取りこぼしても取り直しで上限を出す。押せない日に前の失敗の「もう一度」は出さない
    return :exhausted if comments_budget_exhausted?
    return :failed if article.comments_failed_at.present?

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
