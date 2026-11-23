class PersonaComment < ApplicationRecord
  belongs_to :article
  # 外した人のコメントも戻したときにまた出せるよう、人物の表とは外部キーで結ばず slug で引く
  belongs_to :persona, primary_key: :slug, inverse_of: false

  validates :body, presence: true, allow_nil: true

  scope :by_enabled_personas, -> { joins(:persona).where(personas: { enabled: true }) }
  scope :written, -> { where.not(body: nil) }

  def state
    return :written if body?
    return :failed if failed_at? || stale?

    :writing
  end

  # Job が記録の前に止まると（旧版のワーカーが取った、プロセスが落ちたなど）、本文も失敗も書かれずに残る。
  # 頼み直せるよう、yml の秒数より古い書いている途中は失敗として扱う。鍵が無ければ扱いを変えない
  def stale?
    after = Dopamine.settings.dig(:comments, :stale_after_seconds)
    after.present? && updated_at.present? && updated_at < after.seconds.ago
  end

  def written? = state == :written
  def failed? = state == :failed
  def writing? = state == :writing
end
