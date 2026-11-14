class DailyGoal < ApplicationRecord
  validates :day, presence: true, uniqueness: true

  def achieved?
    achieved_at.present?
  end

  # 開いたのが初めてなら true。読んでから書くと、同時に 2 つの要求が来たときに両方が初めてになるので、条件付きの UPDATE 1 本で決める
  def open_chest!(at: Time.current)
    return false unless achieved?

    opened = self.class.where(id: id, chest_opened_at: nil).update_all(chest_opened_at: at) == 1
    reload
    opened
  end

  # 描画のたびに達成時刻を動かさないよう、完読を判定した時点で記録する。
  def self.achieve_if_reached!(at: Time.current)
    day = ReadingDay.of(at)
    find_by(day: day) || (DailySummary.new(day).reached? ? create!(day: day, achieved_at: at) : nil)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_by!(day: day)
  end
end
