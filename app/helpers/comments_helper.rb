module CommentsHelper
  # 鍵が揃うまで、または有効な人物がいない間は、押しても Job が失敗するだけなので、入口ごと出さない。
  def comments_enabled?
    settings = Dopamine.settings[:comments].to_h
    %i[personas_shown model max_tokens timeout_seconds stream_interval_ms].all? { |key| settings[key].present? } && Persona.enabled.exists?
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

  def comments_budget_remaining
    Claude::Budget.new.remaining
  end

  def comments_state(article, exhausted: false)
    return :ready if article.persona_comments.by_enabled_personas.exists?
    return :exhausted if exhausted || comments_budget_exhausted?

    :closed
  end

  def comments_box_state(shown)
    return :writing if shown.any?(&:writing?)
    return :failed if shown.any?(&:failed?)

    :ready
  end
end
