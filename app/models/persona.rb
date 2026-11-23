class Persona < ApplicationRecord
  normalizes :name, :title, :color, :description, :system_prompt, with: ->(value) { value.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "") }

  scope :ordered, -> { order(:position, :id) }
  scope :enabled, -> { where(enabled: true).ordered }

  SLUG_PREFIX = "persona-".freeze
  SLUG_LETTERS = 8

  before_validation :assign_slug, on: :create, if: -> { slug.blank? }
  before_create :place_last, unless: :position_changed?

  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z]+(-[a-z]+)*\z/ }
  validates :color, format: { with: /\A#\h{6}\z/ }
  validates :name, :title, :description, :system_prompt, presence: true

  private

  # 名前は日本語なので slug に起こせない。slug は応答の型と保存済みコメントの鍵にだけ使う内部の名前なので乱数でよい
  def assign_slug
    self.slug = SLUG_PREFIX + SecureRandom.alphanumeric(SLUG_LETTERS, chars: ("a".."z").to_a)
  end

  def place_last
    self.position = (self.class.maximum(:position) || -1) + 1
  end
end
