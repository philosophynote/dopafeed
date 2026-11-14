RSpec.describe CardHighlights do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }
  let(:today) { Time.zone.local(2026, 10, 20, reset_hour) }
  let(:noon) { today + 8.hours }
  let(:feed) { create(:feed) }

  def card(at, feed: self.feed, tier: Dopamine.base_rarity[:name])
    create(:reading, article: create(:article, feed: feed), tier: tier, opened_at: at - 5.minutes, returned_at: at, completed_at: at)
  end

  def miss(at)
    create(:reading, article: create(:article, feed: feed), opened_at: at - 5.seconds, returned_at: at)
  end

  def highlights(reading)
    described_class.new(reading)
  end

  it "未完の判定には何も起きず、段は small" do
    subject = highlights(miss(noon))
    expect(subject.kinds).to be_empty
    expect(subject.tier).to eq(:small)
  end

  it "今日の 1 枚目は FIRST CARD。そのフィードで初めてなら NEW FEED も付き、段は large" do
    subject = highlights(card(noon))
    expect(subject.kinds).to eq(%i[new_feed first_card])
    expect(subject.lead).to eq(:new_feed)
    expect(subject.rest).to eq(%i[first_card])
    expect(subject.tier).to eq(:large)
  end

  it "読書日は reset_hour で切る。手前の時刻の 1 枚は前の日のものなので、境界の直後の 1 枚は今日の 1 枚目" do
    card(today - 1.minute)
    subject = highlights(card(today + 1.minute))
    expect(subject.kinds).to include(:first_card)
  end

  it "2 枚目からは FIRST CARD でなく n 連続（段は medium）。同じフィードの 2 枚目は NEW FEED でない" do
    card(noon - 10.minutes)
    subject = highlights(card(noon))
    expect(subject.kinds).to eq(%i[combo])
    expect(subject.combo).to eq(2)
    expect(subject.tier).to eq(:medium)
  end

  it "未完の直後の完読は「取り返した」で、連続は 1 から数え直す" do
    card(noon - 20.minutes)
    miss(noon - 10.minutes)
    subject = highlights(card(noon))
    expect(subject.kinds).to eq(%i[recovered])
    expect(subject.combo).to eq(1)
  end

  it "昨日 0 本で、それより前にカードがある日の 1 枚目は COMEBACK" do
    card(noon - 3.days)
    subject = highlights(card(noon))
    expect(subject.kinds).to eq(%i[comeback first_card])
  end

  it "昨日も読んでいたら COMEBACK にならない。初めての日も COMEBACK にならない" do
    card(noon - 1.day)
    expect(highlights(card(noon)).kinds).not_to include(:comeback)
  end

  it "金のカードは段 huge" do
    subject = highlights(card(noon, tier: Dopamine.top_rarity[:name]))
    expect(subject.lead).to eq(:jackpot)
    expect(subject.tier).to eq(:huge)
  end

  describe "NEW RECORD" do
    def run(start, count)
      Array.new(count) { |i| card(start + (i * 10).minutes) }
    end

    it "過去の最長（鍵 cards.record_floor 以上）を今日の連続が初めて超えた 1 枚でだけ出る" do
      run(noon - 2.days, 3)
      run(noon, 3)
      expect(highlights(card(noon + 30.minutes)).kinds.first).to eq(:new_record)
      expect(highlights(card(noon + 40.minutes)).kinds).not_to include(:new_record)
    end

    it "過去の最長に並んだだけでは出ない" do
      run(noon - 2.days, 3)
      run(noon, 2)
      expect(highlights(card(noon + 20.minutes)).kinds).not_to include(:new_record)
    end

    it "過去の最長が鍵 cards.record_floor に届かなければ出ない（読み始めの数日は毎回記録になってしまう）" do
      floor = Dopamine.settings.dig(:cards, :record_floor)
      run(noon - 2.days, floor - 1)
      run(noon - (floor * 10).minutes, floor - 1)
      expect(highlights(card(noon)).kinds).not_to include(:new_record)
    end

    it "鍵の値を上げると、その本数に届かない過去の最長では出ない" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(cards: { record_floor: 4 }))
      run(noon - 2.days, 3)
      run(noon - 30.minutes, 3)
      expect(highlights(card(noon)).kinds).not_to include(:new_record)
    end

    it "鍵が無ければ NEW RECORD は出ない" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(cards: { record_floor: nil }))
      run(noon - 2.days, 3)
      run(noon - 30.minutes, 3)
      expect(highlights(card(noon)).kinds).not_to include(:new_record)
    end
  end

  describe "FEVER" do
    it "鍵 cards.fever_combo に届いた連続は、n 連続の代わりに FEVER" do
      threshold = Dopamine.settings.dig(:cards, :fever_combo)
      (threshold - 1).times { |i| card(noon - ((threshold - i) * 10).minutes) }
      subject = highlights(card(noon))
      expect(subject.kinds).to include(:fever)
      expect(subject.kinds).not_to include(:combo)
      expect(subject.combo).to eq(threshold)
    end

    it "鍵が無ければ FEVER は出ない" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(cards: { fever_combo: nil }))
      9.times { |i| card(noon - ((10 - i) * 10).minutes) }
      expect(highlights(card(noon)).kinds).to include(:combo)
      expect(highlights(Reading.order(:returned_at).last).kinds).not_to include(:fever)
    end
  end

  it "重なったら段の大きい順に並ぶ（金と NEW RECORD と n 連続なら NEW RECORD が先頭、連続は最後）" do
    3.times { |i| card(noon - 2.days + (i * 10).minutes) }
    3.times { |i| card(noon - 40.minutes + (i * 10).minutes) }
    subject = highlights(card(noon, tier: Dopamine.top_rarity[:name]))
    expect(subject.kinds).to eq(%i[new_record jackpot combo])
  end
end
