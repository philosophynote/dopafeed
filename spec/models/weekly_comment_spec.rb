RSpec.describe WeeklyComment do
  let(:week) { Date.new(2026, 11, 9) }

  it "1 週 1 行（week_start は DB でも一意）" do
    described_class.create!(week_start: week, body: "ひとこと")

    expect { described_class.new(week_start: week, body: "もう一つ").save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "週の始まりは月曜に限る" do
    expect(described_class.new(week_start: week + 1, body: "ひとこと")).not_to be_valid
  end

  it "成功の行は本文、失敗の行は失敗の時刻を持つ" do
    expect(described_class.new(week_start: week)).not_to be_valid
    expect(described_class.new(week_start: week, failed_at: Time.current, error: "x")).to be_valid
  end

  describe ".for_week" do
    it "成功した行だけを返す" do
      described_class.create!(week_start: week, failed_at: Time.current, error: "x")
      described_class.create!(week_start: week + 7, body: "ひとこと")

      expect(described_class.for_week(week)).to be_nil
      expect(described_class.for_week(week + 7).body).to eq("ひとこと")
    end
  end

  describe ".record_failure!" do
    it "失敗の行を書き、既に行があれば何もしない" do
      described_class.record_failure!(week, "接続エラー")
      described_class.record_failure!(week, "二度目")

      expect(described_class.sole).to have_attributes(error: "接続エラー", body: nil)
    end
  end
end
