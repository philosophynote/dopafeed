RSpec.describe DailyGoalsHelper do
  let(:duration) { Dopamine.settings.dig(:cards, :reveal_duration_ms) }
  let(:stagger) { Dopamine.settings.dig(:cards, :reveal_stagger_ms).to_i }

  it "フィナーレは前の段が終わってから次を始める（蓋が開き終える → カード → 最後のカードがめくれ終える → 行 → 最後の行が落ち終える → 花火）" do
    timing = helper.finale_timing(card_count: 5, row_count: 3)

    expect(timing[:cards_start]).to eq(timing[:lid_delay] + timing[:lid_duration])
    expect(timing[:rows_start]).to eq(timing[:cards_start] + (stagger * 4) + duration)
    expect(timing[:fireworks_start]).to eq(timing[:rows_start] + (timing[:row_step] * 2) + timing[:row_duration])
  end

  it "カードが 1 枚なら、ずらさずにめくり終えた時刻から行を落とす" do
    timing = helper.finale_timing(card_count: 1, row_count: 3)
    expect(timing[:rows_start]).to eq(timing[:cards_start] + duration)
  end
end
