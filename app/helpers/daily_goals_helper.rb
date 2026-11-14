module DailyGoalsHelper
  # 蓋と中身の行の間合い。報酬の調整値ではなく見た目の間合いなので yml に置かない
  FINALE_LID_DELAY_MS = 200
  FINALE_LID_DURATION_MS = 600
  FINALE_ROW_STEP_MS = 150
  FINALE_ROW_DURATION_MS = 350

  # 各段は前の段が終わってから始める。CSS の遅れと音の遅れに別々に書くと片方だけ直してずれるので、ここで一度だけ求めて変数で渡す
  def finale_timing(card_count:, row_count:)
    duration = Dopamine.settings.dig(:cards, :reveal_duration_ms)
    stagger = Dopamine.settings.dig(:cards, :reveal_stagger_ms).to_i
    cards_start = FINALE_LID_DELAY_MS + FINALE_LID_DURATION_MS
    rows_start = cards_start + (stagger * [ card_count - 1, 0 ].max) + duration
    {
      lid_delay: FINALE_LID_DELAY_MS, lid_duration: FINALE_LID_DURATION_MS, cards_start: cards_start,
      rows_start: rows_start, row_step: FINALE_ROW_STEP_MS, row_duration: FINALE_ROW_DURATION_MS,
      fireworks_start: rows_start + (FINALE_ROW_STEP_MS * [ row_count - 1, 0 ].max) + FINALE_ROW_DURATION_MS
    }
  end

  def finale_style(timing)
    {
      "--lid-delay" => timing[:lid_delay], "--lid-duration" => timing[:lid_duration], "--reveal-start" => timing[:cards_start],
      "--finale-start" => timing[:rows_start], "--finale-step" => timing[:row_step], "--finale-row-duration" => timing[:row_duration],
      "--fireworks-start" => timing[:fireworks_start]
    }.map { |name, ms| "#{name}: #{ms}ms" }.join("; ")
  end
end
