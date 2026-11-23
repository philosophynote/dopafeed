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

  def comments_budget_remaining
    Claude::Budget.new.remaining
  end

  def comments_state(article)
    return :ready if article.persona_comments.by_enabled_personas.exists?
    return :exhausted if comments_budget_exhausted?

    :closed
  end

  # 押しても上限で作れず、組み替える作り済みの人もいないなら、押させずに上限を出す。
  # 押した応答だけで決めると、JS が無いときの戻り先や読み直しでまたボタンが出る
  def comments_next_exhausted?(article, shown)
    return false if comments_budget_remaining.positive?

    unasked = Persona.enabled.where.not(slug: article.persona_comments.select(:persona_id)).exists?
    unasked && (article.persona_comments.by_enabled_personas.pluck(:persona_id) - shown.map(&:persona_id)).empty?
  end

  def comments_box_state(shown)
    return :writing if shown.any?(&:writing?)
    return :failed if shown.any?(&:failed?)

    :ready
  end
end
