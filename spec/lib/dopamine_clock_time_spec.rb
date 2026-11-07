RSpec.describe Dopamine, ".clock_time" do
  def with_push(push)
    allow(described_class).to receive(:settings).and_return(described_class.settings.merge(push: push))
  end

  it "文字列はそのまま、引用符を忘れた六十進数（秒）も HH:MM に戻す。鍵が無ければ nil" do
    with_push(digest_at: "07:30", streak_warning_at: 75_600)
    expect(described_class.clock_time(:digest_at)).to eq("07:30")
    expect(described_class.clock_time(:streak_warning_at)).to eq("21:00")

    with_push({})
    expect(described_class.clock_time(:digest_at)).to be_nil
  end
end
