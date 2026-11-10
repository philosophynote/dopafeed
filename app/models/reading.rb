class Reading < ApplicationRecord
  belongs_to :article

  validates :opened_at, presence: true
  validates :returned_at, presence: true, if: :completed_at
  validates :tier, inclusion: { in: ->(_) { Dopamine.rarity_names } }
  validates :article_id, uniqueness: true

  scope :completed, -> { where.not(completed_at: nil) }
  scope :on, ->(day) { completed.where(completed_at: ReadingDay.range(day)) }

  def self.card_count
    completed.count
  end

  # 二重タップで一意制約に当たったら、先に作られた行を使って再抽選を避ける。
  def self.open!(article, at: Time.current)
    reading = find_or_initialize_by(article: article)
    return reading.reopen!(at: at) if reading.persisted?

    reading.update!(tier: RarityDraw.draw, opened_at: at)
    reading
  rescue ActiveRecord::RecordNotUnique
    find_by!(article: article)
  end

  def completed?
    completed_at.present?
  end

  def jackpot?
    tier == Dopamine.top_rarity[:name]
  end

  def dwell_seconds
    return nil if returned_at.nil?

    (returned_at - opened_at).to_i
  end

  # 端末の時計は信用せず、サーバーの時刻で判定する。2 回目の判定では完読を確定し直さない（ADR 0006）。
  def return!(at: Time.current)
    return self if returned_at.present?

    self.returned_at = at
    self.completed_at = at if at - opened_at >= Dopamine.settings.dig(:read, :complete_after_seconds)
    save!
    DailyGoal.achieve_if_reached!(at: at) if completed?
    self
  end

  # 行の作成から元記事を開くまでの待ち時間は、読書の滞在に含めない。
  def start!(at: Time.current)
    return self if returned_at

    update!(opened_at: at)
    self
  end

  # 読み直しで再抽選すると、同じ記事で出目を引き直せてしまう（ADR 0006）。
  def reopen!(at: Time.current)
    return self if completed?

    update!(opened_at: at, returned_at: nil)
    self
  end

  def combo_count
    return 0 unless completed?

    Combo.new(before: returned_at).count + 1
  end
end
