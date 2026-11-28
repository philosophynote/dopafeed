module PersonasHelper
  SUMMARY_MESSAGES = {
    none: "有効な人物がいないので、記事にコメントの欄は出ません",
    all: "有効 %{enabled} 人。コメントでは %{enabled} 人全員が出ます",
    sampled: "有効 %{enabled} 人。コメントでは %{enabled} 人の中から %{shown} 人が出ます"
  }.freeze

  def personas_summary(shown)
    enabled = Persona.enabled.count
    return SUMMARY_MESSAGES.fetch(:none) if enabled.zero?

    pattern = SUMMARY_MESSAGES.fetch(enabled <= shown ? :all : :sampled)
    format(pattern, enabled: enabled, shown: shown)
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
