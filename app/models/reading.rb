# 読了。1 記事 1 行（ADR 0006）。
# 「読む」のタップで作られ（opened_at と抽選結果 tier）、記事から戻ると returned_at、完読なら completed_at と xp が入る。
# tier は名前だけ持つ。倍率・確率は常に config/dopamine.yml から導く。確定した XP だけ xp に数値で残す。
# 判定と XP の確定は {#return!}（戻った時刻で決める）。抽選は {XpRoulette}、コンボは {Combo}。
#
# @!method self.completed
#   完読した行（completed_at あり）
#   @return [ActiveRecord::Relation<Reading>]
# @!method self.on(day)
#   その読書日（{ReadingDay}）に完読した行
#   @return [ActiveRecord::Relation<Reading>]
class Reading < ApplicationRecord
  belongs_to :article

  validates :opened_at, presence: true
  validates :returned_at, presence: true, if: :completed_at
  validates :tier, inclusion: { in: ->(_) { Dopamine.tier_names } }
  validates :article_id, uniqueness: true
  validates :xp, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :completed, -> { where.not(completed_at: nil) }
  scope :on, ->(day) { completed.where(completed_at: ReadingDay.range(day)) }

  def completed?
    completed_at.present?
  end

  # 記事を開いてアプリに戻るまでの秒数
  #
  # @return [Integer, nil] 戻っていなければ nil
  def dwell_seconds
    return nil if returned_at.nil?

    (returned_at - opened_at).to_i
  end

  # 記事から戻った。滞在が read.complete_after_seconds 以上なら完読として XP を確定する。
  # 2 回目以降の戻りは無視する（1 記事 1 回。visibilitychange と pageshow が両方飛んでも二重に付けない）。
  # 未完なら returned_at だけ残し、xp は 0 のまま未読に戻る
  #
  # @param at [Time] 戻った時刻。サーバーの時計で決める（端末の時計は信用しない）
  # @return [Reading] self
  def return!(at: Time.current)
    return self if returned_at.present?

    self.returned_at = at
    if at - opened_at >= Dopamine.settings.dig(:read, :complete_after_seconds)
      self.completed_at = at
      self.combo_multiplier = Combo.new(before: at).multiplier
      self.xp = (base_xp * combo_multiplier).round
    end
    save!
  end

  # 未完のまま同じ記事をもう一度開いた。滞在を測り直すために opened_at を今にし、tier は使い回す（再抽選しない。ADR 0006）。
  # 完読済みなら何もしない
  #
  # @return [Reading] self
  def reopen!(at: Time.current)
    return self if completed?

    update!(opened_at: at, returned_at: nil)
    self
  end

  # 完読ボーナス = xp.base × ルーレットの倍率。コンボを掛ける前の値
  #
  # @return [Integer]
  def base_xp
    Dopamine.settings.dig(:xp, :base) * Dopamine.tier(tier)[:multiplier]
  end

  # XP の内訳。bonus は完読ボーナス、combo はコンボで上乗せした分、total は確定した xp。
  # 倍率は保存せず yml から導くので、yml を変えると bonus と combo の割り振りは変わるが total は変わらない
  #
  # @return [Hash{Symbol => Integer}]
  def xp_breakdown
    { bonus: base_xp, combo: xp - base_xp, total: xp }
  end

  # この完読を含めた連続完読の本数
  #
  # @return [Integer] 未完なら 0
  def combo_count
    return 0 unless completed?

    Combo.new(before: returned_at).count + 1
  end
end
