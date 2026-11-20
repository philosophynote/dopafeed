# 人物は製品の設定なので DB に置かず、config/personas.yml を正とする。
Persona = Data.define(:id, :name, :title, :color, :description, :system_prompt) do
  def self.all
    @all ||= YAML.load_file(Rails.root.join("config/personas.yml")).fetch("personas").map { |attrs| new(**attrs.symbolize_keys) }.freeze
  end

  def self.ids
    all.map(&:id)
  end

  def self.find(id)
    all.find { |persona| persona.id == id }
  end
end
