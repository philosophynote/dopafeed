module ReadingDay
  def self.reset_hour
    Dopamine.settings.dig(:daily_goal, :reset_hour)
  end

  def self.of(time = Time.current)
    (time.in_time_zone - reset_hour.hours).to_date
  end

  def self.range(date)
    start = date.in_time_zone.change(hour: reset_hour)
    start...(start + 1.day)
  end
end
