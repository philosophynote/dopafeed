# コンボ = 同じ読書日の中で直前の完読が途切れずに続いた数。数だけで、倍率は持たない（ADR 0020）
RSpec.describe Combo do
  let(:settings) { Dopamine.settings }
  let(:reset_hour) { settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }

  def completed_at(time)
    create(:reading, :completed, opened_at: time - 5.minutes, returned_at: time, completed_at: time)
  end

  def incomplete_at(time)
    create(:reading, opened_at: time - 5.seconds, returned_at: time)
  end

  it "完読が無ければ count 0" do
    expect(described_class.new(before: noon).count).to eq(0)
  end

  it "直前の連続完読を数え、未完読で途切れる" do
    completed_at(noon - 40.minutes)
    incomplete_at(noon - 30.minutes)
    completed_at(noon - 20.minutes)
    completed_at(noon - 10.minutes)

    expect(described_class.new(before: noon).count).to eq(2)
  end

  it "before 以降の行は数えない" do
    completed_at(noon + 10.minutes)
    expect(described_class.new(before: noon).count).to eq(0)
  end

  it "前の読書日は数えない" do
    completed_at(Time.zone.local(2026, 10, 20, reset_hour) - 1.minute)
    completed_at(Time.zone.local(2026, 10, 20, reset_hour) + 1.minute)
    expect(described_class.new(before: noon).count).to eq(1)
  end

  it "倍率は持たない" do
    expect(described_class.new(before: noon)).not_to respond_to(:multiplier)
  end
end
