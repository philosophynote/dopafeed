class DailySummary
  attr_reader :day

  def initialize(day = ReadingDay.of)
    @day = day
  end

  def count
    @count ||= readings.count
  end

  def dwell_seconds
    @dwell_seconds ||= readings.pluck(:opened_at, :returned_at).sum { |opened, returned| (returned - opened).to_i }
  end

  def cards
    readings.includes(:article).order(:completed_at, :id)
  end

  def goal
    Dopamine.settings.dig(:daily_goal, :articles)
  end

  def remaining
    [ goal - count, 0 ].max
  end

  def reached?
    count >= goal
  end

  # 現在の本数で判定すると、後から読み足したあとに過去の達成判定が変わってしまう。
  def achieved_by?(reading)
    return false unless reading.completed?

    completed_at = Reading.arel_table[:completed_at]
    id = Reading.arel_table[:id]
    before = completed_at.lt(reading.completed_at).or(completed_at.eq(reading.completed_at).and(id.lteq(reading.id)))
    readings.where(before).count == goal
  end

  def streak_days
    ReadingStreak.days(today: day)
  end

  private

  def readings
    Reading.on(day)
  end
end
