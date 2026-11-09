RSpec.describe ReadingStreak do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }
  let(:today) { Date.new(2026, 10, 20) }
  let(:noon) { today.in_time_zone.change(hour: reset_hour) + 8.hours }

  def complete_on(day, count: 1)
    count.times { create(:reading, :completed, opened_at: day.in_time_zone.change(hour: reset_hour) + 10.hours) }
  end

  it "完読が無ければ 0" do
    expect(described_class.days(today: today)).to eq(0)
  end

  it "昨日まで 3 日連続なら、今日 0 本でも 3（今日はまだ切れていない）" do
    complete_on(today - 3)
    complete_on(today - 2)
    complete_on(today - 1)

    expect(described_class.days(today: today)).to eq(3)
  end

  it "今日も読んでいれば今日を含めて数える" do
    complete_on(today - 1)
    complete_on(today, count: 2)

    expect(described_class.days(today: today)).to eq(2)
  end

  it "昨日が 0 本なら今日読んでいても 1、今日も 0 なら 0" do
    complete_on(today - 2)
    expect(described_class.days(today: today)).to eq(0)

    complete_on(today)
    expect(described_class.days(today: today)).to eq(1)
  end

  it "同じ日に何本読んでも 1 日と数える" do
    complete_on(today - 1, count: 5)

    expect(described_class.days(today: today)).to eq(1)
  end

  it "日付は reset_hour で切る（前日の深夜は前日分）" do
    create(:reading, :completed, opened_at: today.in_time_zone.change(hour: reset_hour) - 1.hour)

    expect(described_class.days(today: today)).to eq(1), "reset_hour の前は前日（today - 1）として連続に数える"
  end

  it "引数なしは今日（ReadingDay.of）" do
    travel_to noon do
      complete_on(today - 1)
      expect(described_class.days).to eq(1)
    end
  end
end
