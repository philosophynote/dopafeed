# 今日はまだ終わっていないので、今日が 0 本でも昨日までの連続を切らない。
module ReadingStreak
  def self.days(today: ReadingDay.of)
    days = Reading.completed.pluck(:completed_at).to_set { |time| ReadingDay.of(time) }
    cursor = days.include?(today) ? today : today - 1
    count = 0
    while days.include?(cursor)
      count += 1
      cursor -= 1
    end
    count
  end
end
