# 連続完読の数。同じ読書日（{ReadingDay}）の中で、ある時刻の直前まで完読が途切れずに続いた数。
# 未完読（読み終えたが complete_after_seconds に満たない）が挟まると 0 から数え直す。
# 判定前の行は数えず、途切れさせもしない（読みかけはまだ結果が出ていない）。
# 数は演出の強さにだけ効き、抽選の確率には効かせない（鍵が無い間は見せるだけ）。
# 時間窓は持たない（鍵が無い間は日付の境界だけで切る）
class Combo
  # @param before [Time] この時刻より前に判定した行だけを見る。確定しようとしている読了自身を含めないため
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
end
