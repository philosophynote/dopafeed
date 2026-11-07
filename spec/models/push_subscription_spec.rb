RSpec.describe PushSubscription do
  it "endpoint・p256dh・auth が要り、endpoint は一意" do
    create(:push_subscription, endpoint: "https://push.example.com/sub/1")

    expect(build(:push_subscription, endpoint: "https://push.example.com/sub/1")).not_to be_valid
    expect(build(:push_subscription, endpoint: "")).not_to be_valid
    expect(build(:push_subscription, p256dh: nil)).not_to be_valid
    expect(build(:push_subscription, auth: nil)).not_to be_valid
    expect(build(:push_subscription, endpoint: "https://push.example.com/sub/2")).to be_valid
  end

  it "endpoint は https だけ受ける（送信先に内部や file を書き込ませない）" do
    expect(build(:push_subscription, endpoint: "http://push.example.com/sub/1")).not_to be_valid
    expect(build(:push_subscription, endpoint: "javascript:alert(1)")).not_to be_valid
  end

  describe ".register" do
    it "同じ endpoint なら行を増やさず鍵と UA を書き換える（端末が購読をやり直したとき）" do
      described_class.register(endpoint: "https://push.example.com/sub/1", p256dh: "old-key", auth: "old-auth", user_agent: "UA 1")

      expect do
        described_class.register(endpoint: "https://push.example.com/sub/1", p256dh: "new-key", auth: "new-auth", user_agent: "UA 2")
      end.not_to change(described_class, :count)

      subscription = described_class.find_by!(endpoint: "https://push.example.com/sub/1")
      expect(subscription).to have_attributes(p256dh: "new-key", auth: "new-auth", user_agent: "UA 2")
    end
  end
end
