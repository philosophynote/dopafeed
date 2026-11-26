module WeeklyHelper
  WEEKDAYS = %w[月 火 水 木 金 土 日].freeze

  def hours_and_minutes(seconds)
    hours, minutes = (seconds / 60).divmod(60)
    hours.positive? ? "#{hours}時間#{minutes}分" : "#{minutes}分"
  end

  def day_state(day, today)
    if day == today then :today
    elsif day > today then :future
    else :past
    end
  end

  def week_change(report)
    return "先週 #{report.previous_count} 本" if report.change_percent.nil?

    format("先週比 %+d%%", report.change_percent)
  end
end
