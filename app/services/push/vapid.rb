module Push
  # credentials を直接読まず、他の鍵と同じ ENV 経由にして環境ごとに有無を切り替えられるようにする。
  # 鍵が揃わないまま購読を受け付けると、送れない購読が残る。
  module Vapid
    KEYS = %w[VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY VAPID_SUBJECT].freeze

    def self.configured?
      KEYS.all? { |key| ENV[key].present? }
    end

    def self.public_key
      ENV["VAPID_PUBLIC_KEY"] if configured?
    end

    def self.private_key
      ENV["VAPID_PRIVATE_KEY"] if configured?
    end

    def self.subject
      ENV["VAPID_SUBJECT"] if configured?
    end
  end
end
