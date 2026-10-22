module Claude
  # 日次の呼び出し上限（ADR 0002）。上限は config/dopamine.yml の claude.daily_call_limit。
  # 「今日」は Time.zone の暦日。daily_goal.reset_hour は読書の日付であって費用の日付ではないので使わない。
  class Budget
    class Exhausted < StandardError; end

    attr_reader :limit

    def self.default_limit
      Rails.application.config_for(:dopamine).dig(:claude, :daily_call_limit)
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

    # 呼ぶ前に 1 回だけ呼ぶ。上限に達していれば行を作らずに Exhausted を投げる（Job は discard_on で止まる）
    def record!(purpose:, model:)
      raise Exhausted, "Claude daily call limit reached (#{used_today}/#{limit})" if exhausted?

      ClaudeApiCall.create!(purpose: purpose, model: model)
    end
  end
end
