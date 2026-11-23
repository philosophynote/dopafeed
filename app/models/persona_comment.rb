class PersonaComment < ApplicationRecord
  belongs_to :article
  # 外した人のコメントも戻したときにまた出せるよう、人物の表とは外部キーで結ばず slug で引く
  belongs_to :persona, primary_key: :slug, inverse_of: false

  # 本文の無い行は、出す人を押した時点で決めて残すための枠
  validates :body, presence: true, allow_nil: true

  scope :by_enabled_personas, -> { joins(:persona).where(personas: { enabled: true }) }
  scope :written, -> { where.not(body: nil) }

  def state
    return :written if body?
    return :failed if failed_at?

    :writing
  end

  def written? = state == :written
  def failed? = state == :failed
  def writing? = state == :writing
end
