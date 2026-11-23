class PersonaComment < ApplicationRecord
  belongs_to :article
  # 外した人のコメントも戻したときにまた出せるよう、人物の表とは外部キーで結ばず slug で引く
  belongs_to :persona, primary_key: :slug, inverse_of: false

  validates :body, presence: true

  scope :by_enabled_personas, -> { joins(:persona).where(personas: { enabled: true }) }
end
