module Push
  # Web Push の VAPID 鍵。ENV の VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY / VAPID_SUBJECT から読む（ADR 0013）。
  # credentials を直接読まず ENV なのは、ログインユーザーや Litestream の鍵と同じ経路（credentials → .kamal/secrets → ENV）に揃え、
  # 鍵の有無を環境ごとに切り替えられるようにするため。3 つ揃っていないときは「無い」と扱い、購読を受け付けない（送れない購読を残さない）
  module Vapid
    KEYS = %w[VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY VAPID_SUBJECT].freeze

    def self.configured?
      KEYS.all? { |key| ENV[key].present? }
    end

    # @return [String, nil] 端末が購読に使う公開鍵（base64url）。揃っていなければ nil
    def self.public_key
      ENV["VAPID_PUBLIC_KEY"] if configured?
    end

    def self.private_key
      ENV["VAPID_PRIVATE_KEY"] if configured?
    end

    # @return [String, nil] mailto: か https: の連絡先。Push サービスが送信者を問い合わせる先
    def self.subject
      ENV["VAPID_SUBJECT"] if configured?
    end
  end
end
