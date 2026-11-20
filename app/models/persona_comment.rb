class PersonaComment < ApplicationRecord
  belongs_to :article

  validates :persona_id, inclusion: { in: ->(_) { Persona.ids } }
  validates :body, presence: true

  def persona
    Persona.find(persona_id)
  end
end
