class Combo
  # 確定しようとしている読了自身を数に含めない。
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

  # readings.combo_multiplier の保存精度を超える値で計算しない。
  def multiplier
    xp = Dopamine.settings[:xp]
    [ (1 + xp[:combo_multiplier_step] * count).round(1), xp[:combo_max_multiplier] ].min
  end
end
