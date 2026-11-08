# 読了。1 記事 1 行（ADR 0006）。完読した行がそのまま図鑑のカード 1 枚になる（ADR 0020）。
# 記事を開いたときに作られ（opened_at と抽選結果 tier）、元の記事を開くと opened_at をその時刻に直し、
# 読み終えると returned_at（判定した時刻）、完読なら completed_at が入る。
# tier はカードの枠の希少度の名前。確率は常に config/dopamine.yml から導き、数値は保存しない。
# 判定は {#return!}（読み終えた時刻で決める）。抽選は {RarityDraw}、連続数は {Combo}。
#
# @!method self.completed
#   完読した行（completed_at あり）= カード
#   @return [ActiveRecord::Relation<Reading>]
# @!method self.on(day)
#   その読書日（{ReadingDay}）に完読した行
#   @return [ActiveRecord::Relation<Reading>]
class Reading < ApplicationRecord
  belongs_to :article

  validates :opened_at, presence: true
  validates :returned_at, presence: true, if: :completed_at
  validates :tier, inclusion: { in: ->(_) { Dopamine.rarity_names } }
  validates :article_id, uniqueness: true

  scope :completed, -> { where.not(completed_at: nil) }
  scope :on, ->(day) { completed.where(completed_at: ReadingDay.range(day)) }

  # 図鑑の枚数 = 完読した行の数。数え方を 1 か所に置く
  #
  # @return [Integer]
  def self.card_count
    completed.count
  end

  # 記事を開く。行が無ければ抽選して作り、未完の行は抽選を使い回して開き直す（ADR 0006）。
  # 同時に作られて一意制約で落ちたら、先に入った行を使う（二重タップ）
  #
  # @return [Reading]
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

  # 頂点の希少度（金）を引いたか。頂点は {Dopamine.top_rarity}
  def jackpot?
    tier == Dopamine.top_rarity[:name]
  end

  # 記事を開いてから読み終えるまでの秒数
  #
  # @return [Integer, nil] 判定の前なら nil
  def dwell_seconds
    return nil if returned_at.nil?

    (returned_at - opened_at).to_i
  end

  # 記事を読み終えた。滞在が read.complete_after_seconds 以上なら完読としてカードを確定する。
  # 2 回目以降は無視する（1 記事 1 回。ADR 0006）。
  # 未完なら returned_at だけ残し、カードにはならず未読に戻る
  #
  # @param at [Time] 読み終えた時刻。サーバーの時計で決める（端末の時計は信用しない）
  # @return [Reading] self
  def return!(at: Time.current)
    return self if returned_at.present?

    self.returned_at = at
    self.completed_at = at if at - opened_at >= Dopamine.settings.dig(:read, :complete_after_seconds)
    save!
    DailyGoal.achieve_if_reached!(at: at) if completed?
    self
  end

  # 元の記事を開いた。滞在は開いた時刻から数える（行ができてから開くまでの時間は読んだうちに入れない）。
  # 判定済みなら何もしない。未完の行も判定済みの滞在は書き換えない（読み直しは {#reopen!}）
  #
  # @return [Reading] self
  def start!(at: Time.current)
    return self if returned_at

    update!(opened_at: at)
    self
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

  # この完読を含めた連続完読の本数
  #
  # @return [Integer] 未完なら 0
  def combo_count
    return 0 unless completed?

    Combo.new(before: returned_at).count + 1
  end
end
