module PersonasHelper
  def personas_summary
    enabled = Persona.enabled.count
    shown = Dopamine.settings.dig(:comments, :personas_shown)
    return "有効な人物がいないので、記事にコメントの欄は出ません" if enabled.zero?
    return "有効 #{enabled} 人。コメントでは #{enabled} 人全員が出ます" if enabled <= shown

    "有効 #{enabled} 人。コメントでは #{enabled} 人の中から #{shown} 人が出ます"
  end

  PERSONA_ERRORS = {
    name: "名前を入力してください",
    title: "肩書きを入力してください",
    color: "色は #RRGGBB で指定してください",
    description: "ひとこと紹介を入力してください",
    system_prompt: "口調の指示を入力してください"
  }.freeze

  def persona_error(persona, attribute)
    return unless persona.errors.include?(attribute)

    tag.p(PERSONA_ERRORS.fetch(attribute), class: "text-sm text-red-600", role: "alert")
  end
end
