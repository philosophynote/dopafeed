RSpec.describe ReadingDay do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }

  it "アプリのタイムゾーンは Tokyo" do
    expect(Time.zone.name).to eq("Tokyo")
  end

  it "reset_hour の 1 分前は前日として数える" do
    time = Time.zone.local(2026, 10, 20, reset_hour) - 1.minute
    expect(described_class.of(time)).to eq(Date.new(2026, 10, 19))
  end

  it "reset_hour ちょうどは当日として数える" do
    time = Time.zone.local(2026, 10, 20, reset_hour)
    expect(described_class.of(time)).to eq(Date.new(2026, 10, 20))
  end

  it "引数なしは現在時刻" do
    travel_to Time.zone.local(2026, 10, 20, reset_hour) + 10.hours do
      expect(described_class.of).to eq(Date.new(2026, 10, 20))
    end
  end

  it "UTC で渡しても Tokyo の reset_hour で切る" do
    tokyo = Time.zone.local(2026, 10, 20, reset_hour) - 1.minute
    expect(described_class.of(tokyo.utc)).to eq(Date.new(2026, 10, 19))
  end

  it "range は reset_hour から翌日の reset_hour 手前まで" do
    range = described_class.range(Date.new(2026, 10, 20))
    expect(range.begin).to eq(Time.zone.local(2026, 10, 20, reset_hour))
    expect(range.end).to eq(Time.zone.local(2026, 10, 21, reset_hour))
    expect(range).to be_exclude_end, "翌日の reset_hour ちょうどは翌日分"
  end

  it "of と range は互いに整合する" do
    day = Date.new(2026, 10, 20)
    range = described_class.range(day)
    expect(described_class.of(range.begin)).to eq(day)
    expect(described_class.of(range.end - 1.second)).to eq(day)
    expect(described_class.of(range.end)).to eq(day + 1)
  end
end
