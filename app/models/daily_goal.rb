class DailyGoal < ApplicationRecord
  validates :day, presence: true, uniqueness: true

  def achieved?
    achieved_at.present?
  end

  # 描画のたびに達成時刻を動かさないよう、完読を判定した時点で記録する。
  def self.achieve_if_reached!(at: Time.current)
    day = ReadingDay.of(at)
    find_by(day: day) || (DailySummary.new(day).reached? ? create!(day: day, achieved_at: at) : nil)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_by!(day: day)
  end
end
