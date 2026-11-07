module Push
  # 1 つの購読に 1 通を送る。web-push gem で本文を暗号化し（RFC 8291）、VAPID で署名する（RFC 8292）。
  # endpoint は端末が申告した URL で信用しないので、送る直前に {HttpGet} と同じ内部ネットワークの判定を通す。
  # 失効・無効（410 / 404）、内部アドレス、暗号化できない鍵の購読は消す（端末が許可し直せば行は作り直される）。
  # それ以外の失敗（5xx・429・接続エラー・DNS の不調）はログに残して行は残し、次の回に送り直す。
  # 何をいつ送るかは {DispatchJob} と {Notice} の責務
  class Sender
    # p256dh / auth が base64 でない、または楕円曲線の点でない購読。暗号化できず、端末が作り直すまで送れない
    class BrokenKey < StandardError; end

    # @param payload [Hash] JSON にして送る内容
    # @return [Boolean] 送れたか
    def deliver(subscription, payload)
      HttpGet.verify_external!(subscription.endpoint)
      push(subscription, payload.to_json)
      true
    rescue HttpGet::TransientError => e
      keep(subscription, e)
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, BrokenKey, HttpGet::Error => e
      discard(subscription, e)
    rescue WebPush::Error, *HttpGet::NETWORK_ERRORS => e
      keep(subscription, e)
    end

    private

    # web-push は壊れた鍵を ArgumentError / OpenSSL::PKey::PKeyError で落とす。この呼び出しの中でだけ「壊れた鍵」と読み替え、
    # 他所の ArgumentError を購読の削除に繋げない
    def push(subscription, message)
      WebPush.payload_send(message: message, endpoint: subscription.endpoint, p256dh: subscription.p256dh, auth: subscription.auth,
                           vapid: { subject: Vapid.subject, public_key: Vapid.public_key, private_key: Vapid.private_key },
                           open_timeout: timeout, read_timeout: timeout)
    rescue ArgumentError, OpenSSL::PKey::PKeyError => e
      raise BrokenKey, e.message
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
