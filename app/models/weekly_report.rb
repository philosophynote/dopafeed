class WeeklyReport
  WEEK_START = :monday
  DAYS = 7

  attr_reader :start_day, :today

  def initialize(today: ReadingDay.of)
    @today = today
    @start_day = today.beginning_of_week(WEEK_START)
  end

  def end_day
    start_day + (DAYS - 1)
  end

  def count
    readings.size
  end

  def previous_count
    @previous_count ||= Reading.completed.where(completed_at: week_range(start_day - DAYS)).count
  end

  def change_percent
    return nil if previous_count.zero?

    ((count - previous_count) * 100r / previous_count).round
  end

  def daily_counts
    tally = readings.map { |reading| ReadingDay.of(reading.completed_at) }.tally
    (start_day..end_day).map { |day| tally.fetch(day, 0) }
  end

  def dwell_seconds
    readings.sum(&:dwell_seconds)
  end

  def tier_counts
    readings.map(&:tier).tally
  end

  def summarized_count
    readings.count { |reading| reading.article.summary.present? }
  end

  # @return [Array<Array(Feed, Integer)>]
  def feed_counts
    readings.map { |reading| reading.article.feed }.tally.sort_by { |feed, count| [ -count, feed.title ] }
  end

  def streak_days
    ReadingStreak.days(today: today)
  end

  def cards
    readings.sort_by { |reading| [ reading.completed_at, reading.id ] }
  end

  private

  def week_range(first_day)
    ReadingDay.range(first_day).begin...ReadingDay.range(first_day + DAYS).begin
  end

  def readings
    @readings ||= Reading.completed.where(completed_at: week_range(start_day)).includes(article: :feed).to_a
  end
end
