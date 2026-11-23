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

  # 欄を取り直すときは ids で同じ組を出す。組み替えの乱数で、出たばかりのカードが別人に変わらないように。
  # 書いている途中、失敗の順に新しく頼んだものを先に出し、作っている人が欄から押し出されないようにする。
  # 人物を外して残りが足りなくなっても、空や欠けた組を出さないよう有効な全員から選び直す。
  def shown_persona_comments(article, except: [], ids: [])
    count = Dopamine.settings.dig(:comments, :personas_shown)
    saved = article.persona_comments.by_enabled_personas.includes(:persona).to_a
    same = saved.select { |comment| comment.id.to_s.in?(ids) }.sort_by { |comment| ids.index(comment.id.to_s) }
    return same if same.any?

    rest = saved.reject { |comment| comment.persona_id.in?(except) }
    pool = rest.size >= count ? rest : saved
    unfinished, written = pool.partition { |comment| !comment.written? }
    (unfinished.sort_by { |comment| [ comment.writing? ? 0 : 1, -comment.updated_at.to_f ] } + written.shuffle).first(count)
  end

  def comments_box_state(shown)
    return :writing if shown.any?(&:writing?)
    return :failed if shown.any?(&:failed?)

    :ready
  end
end
