# 読書の「1 日」。config/dopamine.yml の daily_goal.reset_hour（午前 4 時）で日付が変わる。
# タイムゾーンは Time.zone（config.time_zone = Tokyo）。
module ReadingDay
  # @return [Integer] 日付が切り替わる時（0〜23）。dopamine.yml の daily_goal.reset_hour
  def self.reset_hour
    Dopamine.settings.dig(:daily_goal, :reset_hour)
  end

  # その時刻が属する読書の日付
  #
  # @param time [Time, ActiveSupport::TimeWithZone] 既定は現在時刻。UTC で渡しても Time.zone に直して切る
  def self.of(time = Time.current)
    (time.in_time_zone - reset_hour.hours).to_date
  end

  # その日付の時刻範囲（reset_hour 〜 翌日 reset_hour の手前）。completed_at の絞り込みに使う
  #
  # @return [Range<ActiveSupport::TimeWithZone>] 終端を含まない
  def self.range(date)
    start = date.in_time_zone.change(hour: reset_hour)
    start...(start + 1.day)
  end
end
