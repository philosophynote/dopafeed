module Push
  # 暦日で区切ると reset_hour 前の深夜に二度送るため、読書日で数える（ADR 0013）。
  class Notice
    def self.time_key
      raise NotImplementedError
    end

    def self.sent_on_column
      raise NotImplementedError
    end

    # 範囲外の時刻を change に渡すと、定期実行のたびに ArgumentError で落ちる。
    TIME = /\A(\d{1,2}):(\d{2})\z/
    HOURS = 0...24
    MINUTES = 0...60

    attr_reader :day

    def initialize(day = ReadingDay.of)
      @day = day
    end

    def due?(now = Time.current)
      due_at.present? && now >= due_at
    end

    def due_at
      return @due_at if defined?(@due_at)

      hour, minute = Dopamine.clock_time(self.class.time_key).to_s.match(TIME)&.captures&.map(&:to_i)
      @due_at = day.in_time_zone.change(hour: hour, min: minute) if HOURS.cover?(hour) && MINUTES.cover?(minute)
    end

    def payload
      raise NotImplementedError
    end

    private

    # 閉じている端末ではページの Stimulus でバッジを直せないため、通知にも未読数を含める。
    def unread_count
      Article.unread.count
    end
  end
end
