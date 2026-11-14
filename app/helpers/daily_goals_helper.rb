module DailyGoalsHelper
  # 中身の行を 1 行ずつ落とす間隔。報酬の調整値ではなく見た目の間合いなので yml に置かない
  FINALE_ROW_STEP_MS = 150

  # 花火とファンファーレは同じ時刻に始める。CSS と音の遅れに別々に書くと片方だけ直してずれるので、ここで一度だけ求める
  def finale_timing(card_count:, row_count:)
    cards = Dopamine.settings.dig(:cards, :reveal_duration_ms) + (Dopamine.settings.dig(:cards, :reveal_stagger_ms).to_i * card_count)
    { rows_start: cards, row_step: FINALE_ROW_STEP_MS, fireworks_start: cards + (FINALE_ROW_STEP_MS * row_count) }
  end
end
