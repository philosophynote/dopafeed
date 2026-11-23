RSpec.describe WeeklyReport do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }
  let(:rare) { Dopamine.rarity_names.second }
  let(:common) { Dopamine.base_rarity[:name] }
  # 2026-11-18 は水曜。今週は 11/16（月）〜 11/22（日）
  let(:today) { Date.new(2026, 11, 18) }
  let(:report) { described_class.new(today: today) }

  def at(date, hour: 12)
    Time.zone.local(date.year, date.month, date.day, reset_hour) + (hour - reset_hour).hours
  end

  def complete(completed_at, tier: common, dwell: 4.minutes, article: nil)
    article ||= create(:article)
    create(:reading, article: article, tier: tier, opened_at: completed_at - dwell, returned_at: completed_at, completed_at: completed_at)
  end

  it "週は月曜の reset_hour に始まり、その直前の完読は前の週に入る" do
    monday = Date.new(2026, 11, 16)
    complete(monday.in_time_zone.change(hour: reset_hour) - 1.minute)
    complete(monday.in_time_zone.change(hour: reset_hour))

    expect(report.start_day).to eq(monday)
    expect(report.end_day).to eq(Date.new(2026, 11, 22))
    expect(report.count).to eq(1)
    expect(report.previous_count).to eq(1)
  end

  it "未完の行は数えない" do
    create(:reading, article: create(:article), opened_at: at(today), returned_at: at(today) + 5.seconds)

    expect(report.count).to eq(0)
  end

  it "先週比は小数点以下を四捨五入した百分率（32 本 / 23 本 → +39）" do
    32.times { |i| complete(at(today) - i.minutes) }
    23.times { complete(at(today - 7)) }

    expect(report.count).to eq(32)
    expect(report.previous_count).to eq(23)
    expect(report.change_percent).to eq(39)
  end

  it "先週より減ればマイナス" do
    complete(at(today))
    4.times { complete(at(today - 7)) }

    expect(report.change_percent).to eq(-75)
  end

  it "先週 0 本なら先週比は無い" do
    complete(at(today))

    expect(report.previous_count).to eq(0)
    expect(report.change_percent).to be_nil
  end

  it "曜日別の本数は月曜から日曜の 7 つで、reset_hour の手前は前日に数える" do
    complete(at(Date.new(2026, 11, 16)))
    2.times { complete(at(today)) }
    complete(at(today + 1, hour: reset_hour) - 1.minute)

    expect(report.daily_counts).to eq([ 1, 0, 3, 0, 0, 0, 0 ])
  end

  it "読書時間は今週の完読の滞在の合計" do
    complete(at(today), dwell: 3.minutes)
    complete(at(today), dwell: 90.seconds)
    complete(at(today - 7), dwell: 1.hour)

    expect(report.dwell_seconds).to eq(270)
  end

  it "段ごとの枚数と、要約のある記事の本数を数える" do
    complete(at(today), tier: rare)
    complete(at(today), tier: common, article: create(:article, :unsummarized))
    complete(at(today), tier: nil)

    expect(report.tier_counts).to eq(rare => 1, common => 1, nil => 1)
    expect(report.summarized_count).to eq(2)
  end

  it "フィード別は本数の多い順、同数はフィード名順" do
    zenn, publickey, hatena = %w[Zenn Publickey はてブ].map { |title| create(:feed, title: title) }
    [ hatena, zenn, publickey, zenn ].each { |feed| complete(at(today), article: create(:article, feed: feed)) }

    expect(report.feed_counts.map { |feed, count| [ feed.title, count ] }).to eq([ [ "Zenn", 2 ], [ "Publickey", 1 ], [ "はてブ", 1 ] ])
  end

  it "連続日数は今日までの読んだ日の連続" do
    complete(at(today - 1))
    complete(at(today))

    expect(report.streak_days).to eq(2)
  end
end
