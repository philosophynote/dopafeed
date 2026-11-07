# 連続して読んだ日数。「1 本以上完読した読書日（{ReadingDay}）が途切れずに続いている数」で、ゴール達成日の連続ではない。
# 今日が 0 本でも昨日まで続いていれば数える。今日はまだ終わっておらず、朝に開いた瞬間に「0 日」と見せると続ける気が失せるため。
# 昨日も 0 本なら切れているので 0
module ReadingStreak
  # @param today [Date] 既定は今の読書日。テストと日付境界の検証のために差し替えられる
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
