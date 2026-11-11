module Push
  # reset_hour の 3 時間前では深夜になるため、警告は固定の時刻にする（ADR 0013）。
  class StreakWarning < Notice
    def self.time_key
      :streak_warning_at
    end

    def self.sent_on_column
      :streak_warning_sent_on
    end

    def payload
      summary = DailySummary.new(day)
      return unless summary.count.zero?

      streak = summary.streak_days
      return unless streak.positive?

      { title: "#{streak} 日連続が切れます。#{ReadingDay.reset_hour} 時までに 1 本", body: "1 本読めば #{streak + 1} 日目に続きます",
        path: "/", unread: unread_count, tag: "streak" }
    end
  end
end
