# Push の購読の保存と削除（docs/screens/install.md「許可した Then PushSubscription がサーバーに保存され」「再購読しない」）
RSpec.describe "PushSubscriptions", type: :request do
  let(:vapid) { { "VAPID_PUBLIC_KEY" => "BPublic", "VAPID_PRIVATE_KEY" => "private", "VAPID_SUBJECT" => "mailto:nao@example.com" } }
  let(:payload) { { endpoint: "https://push.example.com/sub/1", keys: { p256dh: "BKey", auth: "auth" } } }

  def post_subscription(body = payload)
    post push_subscription_path, params: body.to_json, headers: { "Content-Type" => "application/json", "User-Agent" => "iPhone PWA" }
  end

  it "未ログインなら保存も削除もしない（401）" do
    with_env(vapid) { post_subscription }
    expect(response).to have_http_status(:unauthorized)
    expect(PushSubscription.count).to eq(0)

    create(:push_subscription, endpoint: "https://push.example.com/sub/1")
    delete push_subscription_path, params: { endpoint: "https://push.example.com/sub/1" }.to_json, headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
    expect(PushSubscription.count).to eq(1)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "endpoint と鍵を保存して 201。同じ endpoint をもう一度送っても行は 1 つ（200）" do
      with_env(vapid) do
        expect { post_subscription }.to change(PushSubscription, :count).by(1)
        expect(response).to have_http_status(:created)
        expect(PushSubscription.last).to have_attributes(endpoint: "https://push.example.com/sub/1", p256dh: "BKey", auth: "auth", user_agent: "iPhone PWA")

        expect { post_subscription }.not_to change(PushSubscription, :count)
        expect(response).to have_http_status(:ok)
      end
    end

    it "鍵が欠けていたり keys の形が壊れていれば 422 で保存しない" do
      with_env(vapid) { post_subscription(endpoint: "https://push.example.com/sub/1", keys: { p256dh: "BKey" }) }
      expect(response).to have_http_status(:unprocessable_entity)

      with_env(vapid) { post_subscription(endpoint: "https://push.example.com/sub/1", keys: "broken") }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PushSubscription.count).to eq(0)
    end

    it "サーバーに VAPID 鍵が無ければ 503 で保存しない（送れない購読を残さない）" do
      with_env("VAPID_PUBLIC_KEY" => nil, "VAPID_PRIVATE_KEY" => nil, "VAPID_SUBJECT" => nil) { post_subscription }

      expect(response).to have_http_status(:service_unavailable)
      expect(PushSubscription.count).to eq(0)
    end

    it "DELETE で endpoint の行を消す（無ければ何もせず 204）" do
      create(:push_subscription, endpoint: "https://push.example.com/sub/1")

      delete push_subscription_path, params: { endpoint: "https://push.example.com/sub/1" }.to_json, headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:no_content)
      expect(PushSubscription.count).to eq(0)

      delete push_subscription_path, params: { endpoint: "https://push.example.com/sub/1" }.to_json, headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:no_content)
    end
  end
end
