# 読書日（{ReadingDay}）1 日ぶんの数。完読の本数・滞在の合計・XP の合計と、今日のゴール（daily_goal.articles）までの残り。
# 同じ数を何か所でも見せるので、数え方をここに 1 つだけ置く。読むだけで書かない。
# 達成の記録（行）は {DailyGoal}、連続した日数は {ReadingStreak}
class DailySummary
  attr_reader :day

  # @param day [Date] 既定は今の読書日
  def initialize(day = ReadingDay.of)
    @day = day
  end

  def count
    @count ||= readings.count
  end

  # 完読した記事を開いてから読み終えるまでの秒の和。未完は数えない（XP も付いていない）
  def dwell_seconds
    @dwell_seconds ||= readings.pluck(:opened_at, :returned_at).sum { |opened, returned| (returned - opened).to_i }
  end

  def xp
    @xp ||= readings.sum(:xp)
  end

  def goal
    Dopamine.settings.dig(:daily_goal, :articles)
  end

  # @return [Integer] 超えても 0 で止める（「あと −1 本」を出さない）
  def remaining
    [ goal - count, 0 ].max
  end

  def reached?
    count >= goal
  end

  # その完読がこの日のちょうど goal 本目か。goal + 1 本目以降と未完は偽。
  # 描いた時点の本数で見ると、後から読み足したあとに前の判定を描き直したときに答えが変わるので、その行までの本数で決める
  def achieved_by?(reading)
    reading.completed? && readings.where(completed_at: ..reading.completed_at).count == goal
  end

  def streak_days
    ReadingStreak.days(today: day)
  end

  private

  def readings
    Reading.on(day)
  end
end
