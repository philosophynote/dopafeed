RSpec.describe Push::StreakWarning do
  let(:day) { Date.new(2026, 11, 7) }

  before { allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(push: { streak_warning_at: "21:00" })) }

  def complete(at)
    create(:reading, :completed, opened_at: at - 5.minutes, returned_at: at, completed_at: at)
  end

  it "push.streak_warning_at を過ぎたら due?" do
    notice = described_class.new(day)
    expect(notice.due?(Time.zone.local(2026, 11, 7, 20, 59))).to be(false)
    expect(notice.due?(Time.zone.local(2026, 11, 7, 21))).to be(true)
  end

  it "昨日まで続いていて今日が 0 本なら、続いた日数と reset_hour を題にする" do
    complete(Time.zone.local(2026, 11, 5, 22))
    complete(Time.zone.local(2026, 11, 6, 23))
    create(:article)

    expect(described_class.new(day).payload).to eq(
      title: "2 日連続が切れます。4 時までに 1 本", body: "1 本読めば 3 日目に続きます", path: "/", unread: 1, tag: "streak"
    )
  end

  it "今日すでに 1 本読んでいれば nil（切れない）" do
    complete(Time.zone.local(2026, 11, 6, 23))
    complete(Time.zone.local(2026, 11, 7, 12))

    expect(described_class.new(day).payload).to be_nil
  end

  it "昨日も 0 本（連続が無い）なら nil。切れたものは警告しない" do
    complete(Time.zone.local(2026, 11, 5, 12))

    expect(described_class.new(day).payload).to be_nil
  end

  it "翌日の reset_hour 前は同じ読書日として今日の本数を見る" do
    complete(Time.zone.local(2026, 11, 6, 23))
    complete(Time.zone.local(2026, 11, 8, 1))

    expect(described_class.new(day).payload).to be_nil
  end
end
