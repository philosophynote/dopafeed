module Push
  # ストリークの警告。昨日まで続いていて今日がまだ 0 本のときだけ「N 日連続が切れます。{reset_hour} 時までに 1 本」。
  # 今日 1 本でも読んでいれば切れないので出さず、昨日も 0 本なら切れた後なので出さない（ADR 0013）。
  # 時刻は dopamine.yml の push.streak_warning_at（reset_hour の 3 時間前は深夜になるので固定の時刻）
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
