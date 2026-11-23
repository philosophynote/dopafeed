class Persona < ApplicationRecord
  scope :ordered, -> { order(:position, :id) }
  scope :enabled, -> { where(enabled: true).ordered }

  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z]+(-[a-z]+)*\z/ }
  validates :color, format: { with: /\A#\h{6}\z/ }
  validates :name, :title, :description, :system_prompt, presence: true
end
