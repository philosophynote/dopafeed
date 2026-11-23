module PersonasHelper
  def personas_summary
    enabled = Persona.enabled.count
    shown = Dopamine.settings.dig(:comments, :personas_shown)
    return "有効な人物がいないので、記事にコメントの欄は出ません" if enabled.zero?
    return "有効 #{enabled} 人。コメントでは #{enabled} 人全員が出ます" if enabled < shown

    "有効 #{enabled} 人。コメントでは #{enabled} 人の中から #{shown} 人が出ます"
  end
end
