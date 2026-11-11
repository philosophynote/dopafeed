module Claude
  # 費用の「今日」は暦日なので、読書用の reset_hour は使わない（ADR 0006）。
  class Budget
    class Exhausted < StandardError; end

    attr_reader :limit

    def self.default_limit
      Dopamine.settings.dig(:claude, :daily_call_limit)
    end

    def initialize(limit: self.class.default_limit)
      @limit = limit
    end

    def used_today
      ClaudeApiCall.where(created_at: Time.current.all_day).count
    end

    def remaining
      [ limit - used_today, 0 ].max
    end

    def exhausted?
      used_today >= limit
    end

    # 数えてから書く間に他のスレッドが入ると上限を超えるため、BEGIN IMMEDIATE の中で行う。
    def record!(purpose:, model:)
      ClaudeApiCall.transaction do
        used = used_today
        raise Exhausted, "Claude daily call limit reached (#{used}/#{limit})" if used >= limit

        ClaudeApiCall.create!(purpose: purpose, model: model)
      end
    end
  end
end
