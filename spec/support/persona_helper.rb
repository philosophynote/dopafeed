module PersonaHelper
  # 本番に入れた初期値と同じ顔ぶれで、カセットの応答の人物 id と揃える
  def seed_personas
    YAML.load_file(Rails.root.join("db/seeds/personas.yml")).fetch("personas").each_with_index.map do |attrs, index|
      Persona.create!(**attrs.symbolize_keys, position: index)
    end
  end
end

RSpec.configure { |config| config.include PersonaHelper }
