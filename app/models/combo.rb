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
end
