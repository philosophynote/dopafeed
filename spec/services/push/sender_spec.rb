# Push の送信（docs/screens/install.md「VAPID 鍵 When サーバーが Push を送る Then web-push gem で送り、410 が返った購読は削除する」）。
# endpoint への POST は WebMock で止め、暗号化と署名は本物の鍵で通す（カセットは使わない）
RSpec.describe Push::Sender do
  let(:vapid_key) { WebPush.generate_key }
  let(:vapid) { { "VAPID_PUBLIC_KEY" => vapid_key.public_key, "VAPID_PRIVATE_KEY" => vapid_key.private_key, "VAPID_SUBJECT" => "mailto:nao@example.com" } }
  let(:subscriber_key) { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:p256dh) { Base64.urlsafe_encode64(subscriber_key.public_key.to_bn.to_s(2), padding: false) }
  let(:auth) { Base64.urlsafe_encode64(SecureRandom.random_bytes(16), padding: false) }
  let(:endpoint) { "https://push.example.com/sub/real" }
  let!(:subscription) { create(:push_subscription, endpoint: endpoint, p256dh: p256dh, auth: auth) }
  let(:payload) { { title: "今日の新着 3 本が届きました", path: "/", unread: 3 } }

  def deliver
    with_env(vapid) { described_class.new.deliver(subscription, payload) }
  end

  it "暗号化した本文を VAPID の署名付きで endpoint に POST し、真を返す" do
    stub_request(:post, endpoint).to_return(status: 201)

    expect(deliver).to be(true)

    expect(a_request(:post, endpoint).with { |req|
      req.headers["Content-Encoding"] == "aes128gcm" && req.headers["Authorization"].start_with?("vapid t=") && req.body.bytesize.positive?
    }).to have_been_made.once
    expect(subscription.reload).to be_persisted
  end

  it "待ち時間を web-push に渡す（既定の 60 秒で Job を止めない）" do
    seconds = Dopamine.settings.dig(:fetch, :timeout_seconds)
    allow(WebPush).to receive(:payload_send).and_return(instance_double(Net::HTTPCreated))

    deliver

    expect(WebPush).to have_received(:payload_send).with(hash_including(open_timeout: seconds, read_timeout: seconds, endpoint: endpoint, p256dh: p256dh, auth: auth,
                                                                        vapid: { subject: "mailto:nao@example.com", public_key: vapid_key.public_key, private_key: vapid_key.private_key }))
  end

  it "410（失効）と 404（無効）が返った購読は消して偽を返す" do
    stub_request(:post, endpoint).to_return(status: 410)
    expect(deliver).to be(false)
    expect(PushSubscription.exists?(subscription.id)).to be(false)

    other = create(:push_subscription, endpoint: "https://push.example.com/sub/gone", p256dh: p256dh, auth: auth)
    stub_request(:post, other.endpoint).to_return(status: 404)
    expect(with_env(vapid) { described_class.new.deliver(other, payload) }).to be(false)
    expect(PushSubscription.exists?(other.id)).to be(false)
  end

  it "401 / 403 は消さない（サーバー側の subject や時計の不備でも出るので、全購読を失わない）" do
    [ 401, 403 ].each do |status|
      stub_request(:post, endpoint).to_return(status: status)
      expect(deliver).to be(false)
    end
    expect(subscription.reload).to be_persisted
  end

  it "5xx・429・413・接続エラーは偽を返すが購読は残し、ログには id と例外の型だけ残す（次の回に送り直す）" do
    log = StringIO.new
    stub_request(:post, endpoint).to_return(status: 503)
    with_rails_logger(Logger.new(log)) { expect(deliver).to be(false) }
    expect(subscription.reload).to be_persisted
    expect(log.string).to include("[push] subscription #{subscription.id} failed: WebPush::PushServiceError")
    expect(log.string).not_to include(endpoint)

    [ 429, 413 ].each do |status|
      stub_request(:post, endpoint).to_return(status: status)
      expect(deliver).to be(false)
    end

    stub_request(:post, endpoint).to_timeout
    expect(deliver).to be(false)
    expect(subscription.reload).to be_persisted
  end

  it "暗号化した本文が大きすぎる（web-push の ArgumentError）のは購読のせいではないので残す" do
    expect(with_env(vapid) { described_class.new.deliver(subscription, payload.merge(body: "あ" * 2000)) }).to be(false)

    expect(a_request(:post, /./)).not_to have_been_made
    expect(subscription.reload).to be_persisted
  end

  it "想定外の例外は error reporter に渡し、購読は残して偽を返す（1 つの購読で残りを止めない）" do
    allow(WebPush).to receive(:payload_send).and_raise(NoMethodError, "boom")
    allow(Rails.error).to receive(:report).and_call_original

    expect(deliver).to be(false)

    expect(Rails.error).to have_received(:report).with(an_instance_of(NoMethodError), hash_including(handled: true))
    expect(subscription.reload).to be_persisted
  end

  it "サーバーの VAPID 鍵が読めなければ ConfigurationError で止まり、購読は消さない（打ち間違い、別のペア、subject が mailto: / https: でない）" do
    other_key = WebPush.generate_key
    [ vapid.merge("VAPID_PRIVATE_KEY" => "broken"), vapid.merge("VAPID_PUBLIC_KEY" => other_key.public_key) ].each do |env|
      expect { with_env(env) { described_class.new } }.to raise_error(described_class::ConfigurationError, /VAPID 鍵が読めません/)
    end
    [ "nao@example.com", "http://example.com", "mailto:" ].each do |subject|
      expect { with_env(vapid.merge("VAPID_SUBJECT" => subject)) { described_class.new } }.to raise_error(described_class::ConfigurationError, /subject/)
    end
    with_env(vapid.merge("VAPID_SUBJECT" => "https://dopafeed.example.com/")) { described_class.new }
    expect(subscription.reload).to be_persisted
  end

  it "endpoint が内部ネットワークを指す購読は送らずに消す（HttpGet と同じ判定）" do
    allow(Resolv).to receive(:getaddresses).with("push.example.com").and_return([ "169.254.169.254" ])

    expect(deliver).to be(false)

    expect(a_request(:post, /./)).not_to have_been_made
    expect(PushSubscription.exists?(subscription.id)).to be(false)
  end

  it "endpoint の名前が引けなければ送らず、購読は残す（DNS の不調で消さない）" do
    allow(Resolv).to receive(:getaddresses).with("push.example.com").and_return([])

    expect(deliver).to be(false)

    expect(a_request(:post, /./)).not_to have_been_made
    expect(subscription.reload).to be_persisted
  end

  it "鍵が壊れていて暗号化できない購読は消す（base64 でない、曲線上の点でない、auth が base64 でない・16 バイトでない）" do
    not_a_point = Base64.urlsafe_encode64("\x04" + "\x01" * 64, padding: false)
    short_auth = Base64.urlsafe_encode64(SecureRandom.random_bytes(8), padding: false)
    [ { p256dh: "BFakeP256dhKey" }, { p256dh: not_a_point }, { auth: "!!!" }, { auth: short_auth } ].each do |broken|
      broken_subscription = create(:push_subscription, endpoint: "https://push.example.com/sub/#{broken.keys.first}", p256dh: p256dh, auth: auth)
      broken_subscription.update_columns(broken)

      expect(with_env(vapid) { described_class.new.deliver(broken_subscription, payload) }).to be(false)
      expect(PushSubscription.exists?(broken_subscription.id)).to be(false)
    end
    expect(a_request(:post, /./)).not_to have_been_made
  end
end
