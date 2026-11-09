module Push
  # 401 / 403 はサーバー側の subject や時計の不備でも起きるため、購読を削除すると全端末を失いうる。
  class Sender
    class BrokenKey < StandardError; end
    class ConfigurationError < StandardError; end

    CURVE = "prime256v1".freeze
    # auth の生バイト数（RFC 8291 3.2）。web-push は長さを見ずに HKDF へ通すので、違う長さでも送れてしまい端末で復号できない
    AUTH_BYTES = 16

    def initialize
      @vapid = { subject: Vapid.subject, public_key: Vapid.public_key, private_key: Vapid.private_key }
      raise ConfigurationError, "VAPID の subject が mailto: か https: ではありません" unless self.class.valid_subject?(@vapid[:subject])

      # from_keys は base64 しか見ない。公開鍵と秘密鍵が別のペアなのは check_key で分かる
      WebPush::VapidKey.from_keys(@vapid[:public_key], @vapid[:private_key]).curve.check_key
    rescue ArgumentError, OpenSSL::OpenSSLError => e
      raise ConfigurationError, "VAPID 鍵が読めません (#{e.class.name})"
    end

    def deliver(subscription, payload)
      HttpGet.verify_external!(subscription.endpoint)
      check_keys!(subscription)
      WebPush.payload_send(message: payload.to_json, endpoint: subscription.endpoint, p256dh: subscription.p256dh, auth: subscription.auth,
                           vapid: @vapid, open_timeout: timeout, read_timeout: timeout)
      true
    rescue HttpGet::TransientError => e
      keep(subscription, e)
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, BrokenKey, HttpGet::Error => e
      discard(subscription, e)
    rescue WebPush::Error, *HttpGet::NETWORK_ERRORS => e
      keep(subscription, e)
    rescue StandardError => e
      # 1 つの購読の想定外で残りの購読ともう一方の通知を道連れにしない。見落とさないよう error reporter にも渡す
      Rails.error.report(e, handled: true, context: { push_subscription_id: subscription.id })
      keep(subscription, e)
    end

    # 正規表現では https:/// のようなホスト無しを通すため、URI に解かせる。
    def self.valid_subject?(subject)
      case (uri = URI(subject.to_s))
      when URI::MailTo then uri.to.present?
      when URI::HTTPS then uri.host.present?
      else false
      end
    rescue URI::Error
      false
    end

    private

    # web-push が暗号化で使う形（曲線上の点と、auth の生バイト）に先に直してみる。web-push の中で落とすと、
    # VAPID 鍵の不備や大きすぎる本文の ArgumentError と見分けが付かず、購読のせいでない失敗で行を消してしまう
    def check_keys!(subscription)
      OpenSSL::PKey::EC::Point.new(OpenSSL::PKey::EC::Group.new(CURVE), OpenSSL::BN.new(WebPush.decode64(subscription.p256dh), 2))
      raise BrokenKey, "auth の長さが違います" unless WebPush.decode64(subscription.auth).bytesize == AUTH_BYTES
    rescue ArgumentError, OpenSSL::OpenSSLError => e
      raise BrokenKey, e.class.name
    end

    def discard(subscription, error)
      Rails.logger.info("[push] subscription #{subscription.id} discarded: #{error.class.name}")
      subscription.destroy
      false
    end

    # endpoint はそれ自体が送信の権限になる URL なので、ログには id と例外の型だけ残す
    def keep(subscription, error)
      Rails.logger.warn("[push] subscription #{subscription.id} failed: #{error.class.name}")
      false
    end

    # web-push の既定（60 秒）は Job を長く止めるので、記事の取得と同じ fetch.timeout_seconds に合わせる
    def timeout
      Dopamine.settings.dig(:fetch, :timeout_seconds)
    end
  end
end
