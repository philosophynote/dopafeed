# 読書日（{ReadingDay}）1 日ぶんの数。完読の本数・滞在の合計と、今日のゴール（daily_goal.articles）までの残り。
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

  # 完読した記事を開いてから読み終えるまでの秒の和。未完は数えない（カードになっていない）
  def dwell_seconds
    @dwell_seconds ||= readings.pluck(:opened_at, :returned_at).sum { |opened, returned| (returned - opened).to_i }
  end

  # その日に手に入れたカード。開封の順（古い完読が先）
  def cards
    readings.includes(:article).order(:completed_at, :id)
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
  # 描いた時点の本数で見ると、後から読み足したあとに前の判定を描き直したときに答えが変わるので、その行までの本数で決める。
  # 同じ時刻の完読は id で順を付け、goal 本目が必ず 1 行になるようにする
  def achieved_by?(reading)
    return false unless reading.completed?

    completed_at = Reading.arel_table[:completed_at]
    id = Reading.arel_table[:id]
    before = completed_at.lt(reading.completed_at).or(completed_at.eq(reading.completed_at).and(id.lteq(reading.id)))
    readings.where(before).count == goal
  end

  def streak_days
    ReadingStreak.days(today: day)
  end

  private

  def readings
    Reading.on(day)
  end
end
