class Reading < ApplicationRecord
  belongs_to :article

  validates :opened_at, presence: true
  validates :returned_at, presence: true, if: :completed_at
  validates :tier, inclusion: { in: ->(_) { Dopamine.rarity_names } }, allow_nil: true
  validates :article_id, uniqueness: true

  scope :completed, -> { where.not(completed_at: nil) }
  scope :on, ->(day) { completed.where(completed_at: ReadingDay.range(day)) }

  def self.card_count
    completed.count
  end

  def self.open!(article, at: Time.current)
    reading = find_or_initialize_by(article: article)
    if reading.persisted?
      # 判定の知らせより後に残った空の枠は、ほかに書く者がいない。
      reading.update!(tier: tier_at_open(article)) if reading.tier.nil?
      return reading.reopen!(at: at)
    end

    reading.update!(tier: tier_at_open(article), opened_at: at)
    reading
  rescue ActiveRecord::RecordNotUnique
    find_by!(article: article)
  end

  # 枠は判定が届くまで空にしておく。判定を積めない環境では待っても届かないので、最初から一番下の段にする。
  def self.tier_at_open(article)
    article.judgment&.tier || (Dopamine.base_rarity[:name] unless Judgments::ArticleScorer.configured?)
  end
  private_class_method :tier_at_open

  # 一度決まった枠は書き換えない。境界を後で変えても、手に入れたカードが勝手に変わらないようにする。
  #
  # @return [Reading, nil] この呼び出しで枠が決まった行
  def self.settle_tier!(article)
    tier = ArticleJudgment.find_by(article_id: article.id)&.tier || Dopamine.base_rarity[:name]
    find_by(article_id: article.id) if where(article_id: article.id, tier: nil).update_all(tier: tier) == 1
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
