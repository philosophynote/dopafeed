class Reading < ApplicationRecord
  belongs_to :article

  validates :opened_at, presence: true
  validates :returned_at, presence: true, if: :completed_at
  validates :tier, inclusion: { in: ->(_) { Dopamine.tier_names } }
  validates :article_id, uniqueness: true
  validates :xp, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :completed, -> { where.not(completed_at: nil) }
  scope :on, ->(day) { completed.where(completed_at: ReadingDay.range(day)) }

  # 二重タップで一意制約に当たったら、先に作られた行を使って再抽選を避ける。
  def self.open!(article, at: Time.current)
    reading = find_or_initialize_by(article: article)
    return reading.reopen!(at: at) if reading.persisted?

    reading.update!(tier: XpRoulette.draw, opened_at: at)
    reading
  rescue ActiveRecord::RecordNotUnique
    find_by!(article: article)
  end

  def completed?
    completed_at.present?
  end

  def jackpot?
    tier == Dopamine.jackpot_tier[:name]
  end

  def dwell_seconds
    return nil if returned_at.nil?

    (returned_at - opened_at).to_i
  end

  # 端末の時計は信用せず、サーバーの時刻で判定する。2 回目の判定では XP を加算しない（ADR 0006）。
  def return!(at: Time.current)
    return self if returned_at.present?

    self.returned_at = at
    if at - opened_at >= Dopamine.settings.dig(:read, :complete_after_seconds)
      self.completed_at = at
      self.combo_multiplier = Combo.new(before: at).multiplier
      self.xp = (base_xp * combo_multiplier).round
    end
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

  def base_xp
    Dopamine.settings.dig(:xp, :base) * Dopamine.tier(tier)[:multiplier]
  end

  # 倍率は保存しないため、yml の変更後は bonus と combo の内訳だけが変わり、確定した total は変わらない。
  def xp_breakdown
    { bonus: base_xp, combo: xp - base_xp, total: xp }
  end

  def combo_count
    return 0 unless completed?

    Combo.new(before: returned_at).count + 1
  end
end
