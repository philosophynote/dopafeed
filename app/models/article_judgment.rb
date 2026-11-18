# 段は 0 始まりの小数のまま保存する。整数に丸めて保存すると、境界の決め方を後で変えたときに元の値へ戻せない。
class ArticleJudgment < ApplicationRecord
  AXES = %w[originality depth practicality evidence insight applicability].freeze
  LEVELS = 5

  belongs_to :article

  validates(*AXES, numericality: { in: 0..(LEVELS - 1) }, allow_nil: true)

  scope :judged, -> { where.not(judged_at: nil) }
  scope :failed, -> { where.not(failed_at: nil) }

  def judged?
    judged_at.present?
  end

  # @return [Hash{String => Integer}, nil] 軸ごとの 1〜LEVELS の点。失敗の行は nil
  def points
    AXES.index_with { |axis| self[axis].round + 1 } if judged?
  end

  # 小数の和を丸めると、見せている 6 つの点の和と合計がずれる。
  def total
    points&.values&.sum
  end
end
