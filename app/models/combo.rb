# 連続完読の倍率。同じ読書日（{ReadingDay}）の中で、ある時刻の直前まで完読が途切れずに続いた数 n から
# 1 + xp.combo_multiplier_step × n を出し、xp.combo_max_multiplier で止める。
# 未完読（戻ったが complete_after_seconds に満たない）が挟まると 0 から数え直す。
# 開いたまま戻っていない行は数えず、途切れさせもしない（読みかけはまだ結果が出ていない）。
# 時間窓は持たない（鍵が無い間は日付の境界だけで切る）
class Combo
  # @param before [Time] この時刻より前に戻った行だけを見る。確定しようとしている読了自身を含めないため
  def initialize(before: Time.current)
    @before = before
  end

  def count
    @count ||= Reading.where(returned_at: ReadingDay.range(ReadingDay.of(@before)).begin...@before)
                      .order(returned_at: :desc)
                      .pluck(:completed_at)
                      .take_while(&:present?)
                      .size
  end

  # @return [Float] 小数 1 桁（readings.combo_multiplier の精度に合わせる）
  def multiplier
    xp = Dopamine.settings[:xp]
    [ (1 + xp[:combo_multiplier_step] * count).round(1), xp[:combo_max_multiplier] ].min
  end
end
