module Push
  # 1 日 1 回の通知の共通の形: dopamine.yml の時刻（push.*_at）をその読書日の中で過ぎたかの判定と、文面の入口。
  # 文面と「今日は出さない」条件は継承側（{Digest} / {StreakWarning}）が payload で決める。
  # 送った印（push_subscriptions の *_sent_on）を読み書きするのは {DispatchJob} で、ここは日付と時刻しか知らない。
  # 日付が読書日（{ReadingDay}）なのは、reset_hour 前の深夜も「同じ日」として二度送らないため（ADR 0013）
  class Notice
    # @return [Symbol] dopamine.yml の push の下の時刻の鍵
    def self.time_key
      raise NotImplementedError
    end

    # @return [Symbol] push_subscriptions の「送った読書日」の列
    def self.sent_on_column
      raise NotImplementedError
    end

    attr_reader :day

    # @param day [Date] 読書日
    def initialize(day = ReadingDay.of)
      @day = day
    end

    # 鍵が無ければ偽のまま（nao が時刻を足すまで通知は無い）
    def due?(now = Time.current)
      due_at.present? && now >= due_at
    end

    # @return [ActiveSupport::TimeWithZone, nil] 読書日の日付に yml の時刻を当てたもの。鍵が無ければ nil
    def due_at
      return @due_at if defined?(@due_at)

      time = Dopamine.clock_time(self.class.time_key)
      hour, minute = time&.split(":")&.map(&:to_i)
      @due_at = time && day.in_time_zone.change(hour: hour, min: minute)
    end

    # @return [Hash, nil] 端末に送る内容（title / body / path / unread / tag）。今日は出さないなら nil
    def payload
      raise NotImplementedError
    end

    private

    # service worker がアイコンのバッジに書き直す数。通知を受けた端末は開かれていないことが多く、
    # ページの Stimulus では直せないのでここに載せる
    def unread_count
      Article.unread.count
    end
  end
end
