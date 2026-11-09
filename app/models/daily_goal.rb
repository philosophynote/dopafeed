class DailyGoal < ApplicationRecord
  validates :day, presence: true, uniqueness: true

  def achieved?
    achieved_at.present?
  end

  # 描画時に記録すると、開いた回数でボーナスが増えてしまう。
  def self.achieve_if_reached!(at: Time.current)
    day = ReadingDay.of(at)
    find_by(day: day) || (DailySummary.new(day).reached? ? create!(day: day, achieved_at: at, bonus_xp: bonus_xp_setting) : nil)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_by!(day: day)
  end

  def self.bonus_xp_setting
    Dopamine.settings.dig(:daily_goal, :bonus_xp).to_i
  end

  def self.bonus_total
    sum(:bonus_xp)
  end
end
