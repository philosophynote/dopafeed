module Push
  # 1 つの購読に 1 通を送る。web-push gem で本文を暗号化し（RFC 8291）、VAPID で署名する（RFC 8292）。
  # endpoint は端末が申告した URL で信用しないので、送る直前に {HttpGet} と同じ内部ネットワークの判定を通す。
  # 消すのは購読そのものが使えないと分かったときだけ: 失効・無効（410 / 404）、内部アドレス、暗号化に使えない p256dh / auth。
  # 端末が許可し直せば行は作り直される。401 / 403 は消さない: VAPID 鍵の交換後の古い購読でも出るが、subject の不備や時計のずれなど
  # サーバー側の原因でも出て、そのとき消すと全購読を失う（交換のときは runbook の手順で行を消す）。
  # それ以外の失敗（5xx・429・413・接続エラー・DNS の不調・想定外の例外）もログに残して行は残し、次の回に送り直す。
  # サーバー側の VAPID 鍵が鍵として読めない・subject が mailto: / https: でないときは購読のせいではないので、1 行も消さずに最初から止める。
  # 何をいつ送るかは {DispatchJob} と {Notice} の責務
  class Sender
    # 購読の p256dh / auth が base64 でない、または楕円曲線の点でない。端末が作り直すまで送れない
    class BrokenKey < StandardError; end
    # ENV の VAPID 鍵が鍵として読めない（打ち間違い、公開鍵と秘密鍵が別のペア）、subject が mailto: / https: でない
    class ConfigurationError < StandardError; end

    CURVE = "prime256v1".freeze
    # Push サービスが VAPID の subject として受け付ける形（RFC 8292 2.1）。外れると 401 / 403 が全購読に返る
    SUBJECT = %r{\A(mailto:[^@\s]+@[^@\s]+|https://\S+)\z}
    # auth の生バイト数（RFC 8291 3.2）。web-push は長さを見ずに HKDF へ通すので、違う長さでも送れてしまい端末で復号できない
    AUTH_BYTES = 16

    # @raise [ConfigurationError]
    def initialize
      @vapid = { subject: Vapid.subject, public_key: Vapid.public_key, private_key: Vapid.private_key }
      raise ConfigurationError, "VAPID の subject が mailto: か https: ではありません" unless SUBJECT.match?(@vapid[:subject].to_s)

      # from_keys は base64 しか見ない。公開鍵と秘密鍵が別のペアなのは check_key で分かる
      WebPush::VapidKey.from_keys(@vapid[:public_key], @vapid[:private_key]).curve.check_key
    rescue ArgumentError, OpenSSL::OpenSSLError => e
      raise ConfigurationError, "VAPID 鍵が読めません (#{e.class.name})"
    end

    # @param payload [Hash] JSON にして送る内容
    # @return [Boolean] 送れたか
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
