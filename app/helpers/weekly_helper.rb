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

  def week_range(first_day, last_day)
    "#{first_day.strftime("%-m/%-d")} – #{last_day.strftime("%-m/%-d")}"
  end

  # 画像は画面と同じ言い回しで描くので、文言はここで組み立てて渡す（JS に日本語の組み立てを持たせない）
  def weekly_share_card(report, comment)
    top_feed, top_count = report.feed_counts.first
    {
      title: "今週のレポート", range: week_range(report.start_day, report.end_day), streak: "#{report.streak_days} 日連続",
      count: report.count, change: [ week_change(report), ("（#{report.previous_count} 本）" if report.change_percent) ].join,
      up: report.change_percent.to_i.positive?,
      days: report.daily_counts.each_with_index.map { |count, i| { label: WEEKDAYS[i], count: count, state: day_state(report.start_day + i, report.today) } },
      stats: [ [ "読書時間", hours_and_minutes(report.dwell_seconds) ], [ "カード", "#{report.count} 枚" ], [ "ひとこと要約", "#{report.summarized_count} 本" ],
               ([ "よく読んだフィード", top_feed.title, top_count.to_s ] if top_feed) ].compact,
      comment: (comment && { label: "Claude のひとこと ・ #{week_range(comment.week_start, comment.week_end)} の週", body: comment.body }),
      footer: "DopaFeed ・ 過去の自分と比べる週次カード"
    }
  end
end
