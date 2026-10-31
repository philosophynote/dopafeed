# 読了。1 記事 1 行（ADR 0006）。
# 「読む」のタップで作られ（opened_at と抽選結果 tier）、記事から戻ると returned_at、完読なら completed_at と xp が入る。
# tier は名前だけ持つ。倍率・確率は常に config/dopamine.yml から導く。確定した XP だけ xp に数値で残す。
# XP の計算・抽選・コンボはここに書かない（Unit 5〜7 がそれぞれの受け入れ条件と一緒に書く）。
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

  # 記事を開いてアプリに戻るまでの秒数。戻っていなければ nil
  def dwell_seconds
    return nil if returned_at.nil?

    (returned_at - opened_at).to_i
  end
end
