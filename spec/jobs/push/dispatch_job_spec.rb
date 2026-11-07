# 10 分おきに回り、時刻を過ぎていて今日の印が無い購読に送って日付を書く（ADR 0013）
RSpec.describe Push::DispatchJob, type: :job do
  let(:vapid) { { "VAPID_PUBLIC_KEY" => "BPublic", "VAPID_PRIVATE_KEY" => "private", "VAPID_SUBJECT" => "mailto:nao@example.com" } }
  let(:sender) { instance_double(Push::Sender, deliver: true) }
  let(:digest) { { title: "今日の新着 1 本が届きました", path: "/", unread: 1, tag: "digest" } }
  let(:warning) { { title: "2 日連続が切れます。4 時までに 1 本", path: "/", unread: 1, tag: "streak" } }

  before do
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(push: { digest_at: "07:30", streak_warning_at: "21:00" }))
    allow(Push::Sender).to receive(:new).and_return(sender)
    allow_any_instance_of(Push::Digest).to receive(:payload).and_return(digest)
    allow_any_instance_of(Push::StreakWarning).to receive(:payload).and_return(warning)
  end

  def run(at)
    travel_to(at) { with_env(vapid) { described_class.perform_now } }
  end

  it "digest_at を過ぎたら印の無い購読全部にダイジェストを送り、その読書日を digest_sent_on に書く。同じ日は二度送らない" do
    subscriptions = create_list(:push_subscription, 2)

    run(Time.zone.local(2026, 11, 7, 7, 35))

    subscriptions.each do |subscription|
      expect(sender).to have_received(:deliver).with(subscription, digest).once
      expect(subscription.reload.digest_sent_on).to eq(Date.new(2026, 11, 7))
      expect(subscription.streak_warning_sent_on).to be_nil
    end

    run(Time.zone.local(2026, 11, 7, 12))
    expect(sender).to have_received(:deliver).exactly(2).times
  end

  it "時刻の前は何も送らない。前の日の印なら送る" do
    subscription = create(:push_subscription, digest_sent_on: Date.new(2026, 11, 6))

    run(Time.zone.local(2026, 11, 7, 7, 20))
    expect(sender).not_to have_received(:deliver)

    run(Time.zone.local(2026, 11, 7, 7, 30))
    expect(sender).to have_received(:deliver).with(subscription, digest).once
    expect(subscription.reload.digest_sent_on).to eq(Date.new(2026, 11, 7))
  end

  it "21:00 を過ぎたら警告も送る。2 種は別々の印。翌日の reset_hour 前はまだ同じ読書日なので送り直さない" do
    subscription = create(:push_subscription, digest_sent_on: Date.new(2026, 11, 7))

    run(Time.zone.local(2026, 11, 7, 21, 5))
    expect(sender).to have_received(:deliver).with(subscription, warning).once
    expect(subscription.reload.streak_warning_sent_on).to eq(Date.new(2026, 11, 7))

    run(Time.zone.local(2026, 11, 8, 2))
    expect(sender).to have_received(:deliver).once
  end

  it "送れなかった購読には印を付けない（次の回に送り直す）。消された購読は触らない" do
    failed, destroyed = create_list(:push_subscription, 2)
    allow(sender).to receive(:deliver).with(failed, digest).and_return(false)
    allow(sender).to receive(:deliver).with(destroyed, digest) { destroyed.destroy!; false }

    run(Time.zone.local(2026, 11, 7, 8))

    expect(failed.reload.digest_sent_on).to be_nil
    expect(PushSubscription.exists?(destroyed.id)).to be(false)
  end

  it "通知が「今日は出さない」（payload が nil）なら送らず印も付けない。条件が整った回に送る" do
    allow_any_instance_of(Push::StreakWarning).to receive(:payload).and_return(nil)
    subscription = create(:push_subscription, digest_sent_on: Date.new(2026, 11, 7))

    run(Time.zone.local(2026, 11, 7, 21, 5))
    expect(sender).not_to have_received(:deliver)
    expect(subscription.reload.streak_warning_sent_on).to be_nil
  end

  it "印の無い購読が無ければ文面を組み立てない" do
    create(:push_subscription, digest_sent_on: Date.new(2026, 11, 7))
    expect_any_instance_of(Push::Digest).not_to receive(:payload)

    run(Time.zone.local(2026, 11, 7, 8))
  end

  it "VAPID 鍵が無ければ何もしない" do
    create(:push_subscription)

    travel_to(Time.zone.local(2026, 11, 7, 8)) { with_env(vapid.transform_values { nil }) { described_class.perform_now } }

    expect(sender).not_to have_received(:deliver)
  end

  it "yml に時刻の鍵が無ければ送らない" do
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.except(:push))
    create(:push_subscription)

    run(Time.zone.local(2026, 11, 7, 23))

    expect(sender).not_to have_received(:deliver)
  end
end
