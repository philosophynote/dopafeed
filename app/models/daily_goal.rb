# 今日のゴール（宝箱）。1 日（{ReadingDay}）につき 1 行。
# achieved_at が入ったら宝箱は開いた（2 回目は開かない）
class DailyGoal < ApplicationRecord
  validates :day, presence: true, uniqueness: true

  def achieved?
    achieved_at.present?
  end
end
