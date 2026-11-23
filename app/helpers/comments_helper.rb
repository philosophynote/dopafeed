module CommentsHelper
  # 鍵が揃うまで、または有効な人物がいない間は、押しても Job が失敗するだけなので、入口ごと出さない。
  def comments_enabled?
    settings = Dopamine.settings[:comments].to_h
    %i[personas_shown model max_tokens timeout_seconds].all? { |key| settings[key].present? } && Persona.enabled.exists?
  end

  def comments_lineup
    enabled = Persona.enabled.count
    shown = Dopamine.settings.dig(:comments, :personas_shown)
    return "#{enabled} 人全員が現れます" if enabled <= shown

    "#{enabled} 人の中から #{shown} 人がランダムに現れます"
  end

  def comments_budget_exhausted?
    Claude::Budget.new.exhausted?
  end

  def comments_state(article, exhausted: false)
    return :ready if article.persona_comments.by_enabled_personas.exists?
    return :exhausted if exhausted || comments_budget_exhausted?

    :closed
  end

  # 書いている途中と失敗の枠を先に出し、読み直しや別の組の後でも作っている人が欄から消えないようにする。
  # 人物を外して残りが足りなくなっても、空や欠けた組を出さないよう有効な全員から選び直す。
  def shown_persona_comments(article, except: [])
    count = Dopamine.settings.dig(:comments, :personas_shown)
    saved = article.persona_comments.by_enabled_personas.includes(:persona).to_a
    rest = saved.reject { |comment| comment.persona_id.in?(except) }
    pool = rest.size >= count ? rest : saved
    unfinished, written = pool.partition { |comment| !comment.written? }
    (unfinished.sort_by(&:created_at).reverse + written.shuffle).first(count)
  end

  def comments_box_state(shown)
    return :writing if shown.any?(&:writing?)
    return :failed if shown.any?(&:failed?)

    :ready
  end
end
