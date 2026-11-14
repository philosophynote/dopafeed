class CardHighlights
  TIERS = {
    huge: %i[new_record jackpot],
    large: %i[comeback recovered new_feed first_card],
    medium: %i[fever combo]
  }.freeze
  # 過去の最長がこれ未満なら記録と呼ばない（読み始めの数日は毎回記録になってしまう）
  RECORD_FLOOR = 2

  def initialize(reading)
    @reading = reading
  end

  def kinds
    @kinds ||= @reading.completed? ? TIERS.values.flatten.select { |kind| send(:"#{kind}?") } : []
  end

  def lead
    kinds.first
  end

  def rest
    kinds.drop(1)
  end

  def tier
    lead ? TIERS.find { |_, list| list.include?(lead) }.first : :small
  end

  def combo
    @combo ||= @reading.combo_count
  end

  private

  def day
    ReadingDay.of(@reading.returned_at)
  end

  # 同じ時刻の行が並んでも前後が揺れないよう、id で順を決める（DailySummary#achieved_by? と同じ）
  def earlier_cards
    completed_at = Reading.arel_table[:completed_at]
    id = Reading.arel_table[:id]
    Reading.completed.where(completed_at.lt(@reading.completed_at).or(completed_at.eq(@reading.completed_at).and(id.lt(@reading.id))))
  end

  # 記録を超えるには連続が床より長い必要があるので、それまでは全履歴を読まずに済ませる
  def new_record?
    return false if combo <= RECORD_FLOOR

    record = longest_combo_before(chain_start)
    record >= RECORD_FLOOR && combo == record + 1
  end

  def jackpot?
    @reading.jackpot?
  end

  def comeback?
    first_card? && !Reading.on(day - 1).exists? && earlier_cards.where(completed_at: ...ReadingDay.range(day - 1).begin).exists?
  end

  def recovered?
    previous = Reading.where(returned_at: ReadingDay.range(day).begin...@reading.returned_at).order(returned_at: :desc).first
    previous.present? && !previous.completed?
  end

  def new_feed?
    !earlier_cards.joins(:article).exists?(articles: { feed_id: @reading.article.feed_id })
  end

  def first_card?
    !earlier_cards.exists?(completed_at: ReadingDay.range(day))
  end

  def fever?
    threshold = Dopamine.settings.dig(:cards, :fever_combo)
    threshold.present? && combo >= threshold
  end

  def combo?
    combo >= 2 && !fever?
  end

  # 今の連続に入っている行は記録の比べ相手から外す（外さないと、記録を超えた後の 1 枚ごとに NEW RECORD が出る）
  def chain_start
    Reading.where(returned_at: ReadingDay.range(day).begin...@reading.returned_at)
           .order(returned_at: :desc).limit(combo - 1).pluck(:returned_at).last || @reading.returned_at
  end

  # 行ごとに読書日へ直すと件数ぶん in_time_zone が走るので、日の終わりを越えたときだけ求め直す
  def longest_combo_before(time)
    best = run = 0
    day_end = nil
    Reading.where(returned_at: ...time).order(:returned_at).pluck(:returned_at, :completed_at).each do |returned_at, completed_at|
      if day_end.nil? || returned_at >= day_end
        day_end = ReadingDay.range(ReadingDay.of(returned_at)).end
        run = 0
      end
      run = completed_at ? run + 1 : 0
      best = run if run > best
    end
    best
  end
end
