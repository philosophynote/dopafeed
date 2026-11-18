module ReadingsHelper
  def dwell_in_words(seconds)
    return "" if seconds.nil?

    minutes, rest = seconds.divmod(60)
    minutes.positive? ? "#{minutes}分#{rest}秒" : "#{rest}秒"
  end

  # 保存に使う希少度の英字名を、表示の翻訳に依存させない。
  def rarity_label(name)
    I18n.t("dopamine.rarities.#{name}", locale: :ja, default: name)
  end

  # @param name [String, nil] 判定中（nil）は段の名を付けない
  def card_name(name)
    name ? "#{rarity_label(name)}カード" : "カード"
  end

  def base_rarity?(name)
    name == Dopamine.base_rarity[:name]
  end

  # 間の段の色は下から順。名前で引くと yml の綴りに縛られるので、並び順で引く。
  MIDDLE_TONES = [ "bg-orange-500 text-white", "bg-purple-600 text-white" ].freeze

  # @param base [String] 一番下の段と、判定中（nil）の色
  def rarity_tone(name, base:)
    if name.nil? || base_rarity?(name) then base
    elsif name == Dopamine.top_rarity[:name] then "bg-amber-400 text-amber-950"
    else middle_rarity_style(name, MIDDLE_TONES)
    end
  end

  def middle_rarity_style(name, styles)
    styles.fetch(Dopamine.rarity_names.index(name) - 1, styles.last)
  end

  # 一番下の段は鳴らさない（毎回鳴ると、上の段が出たときに効かなくなる）
  def rarity_cue(name)
    if name == Dopamine.top_rarity[:name] then "gold"
    elsif !base_rarity?(name) then "rare"
    end
  end

  # 1 周だけだと頂点の手前で止まるとき回った感じが出ないので、段を 2 周させてから止める
  def reel_labels(tier)
    names = Dopamine.rarity_names
    (names * 2 + names.take(names.index(tier))).map { |name| rarity_label(name) }
  end

  # 判定を待つ間は段を回し続ける。最後に先頭の段をもう一度積み、継ぎ目なく繰り返す
  def pending_reel_labels
    names = Dopamine.rarity_names
    (names + names.take(1)).map { |name| rarity_label(name) }
  end

  # @return [String, nil] 枠の根拠。点が無いまま一番下の段に決まった行は、判定できなかったと添える
  def judgment_note(reading)
    total = reading.article.judgment&.total
    if reading.tier.nil? then "判定中"
    elsif total then "#{total} 点"
    elsif base_rarity?(reading.tier) then "判定できず"
    end
  end

  def highlight_label(kind, highlights)
    case kind
    when :new_record then "NEW RECORD! #{highlights.combo} 連続"
    when :jackpot then "#{card_name(Dopamine.top_rarity[:name])}！"
    when :comeback then "COMEBACK!"
    when :recovered then "取り返した！"
    when :new_feed then "NEW FEED!"
    when :first_card then "FIRST CARD!"
    when :fever then "FEVER! #{highlights.combo} 連続"
    when :combo then "#{highlights.combo} 連続！"
    end
  end

  def highlight_cue(highlights)
    { small: "card", medium: "combo", large: "highlight", huge: "fanfare" }.fetch(highlights.tier)
  end

  def daily_goal_line(summary)
    rest = summary.remaining
    "今日のゴール #{summary.count} / #{summary.goal} ・ #{rest.positive? ? "あと #{rest} 本で宝箱" : "読み切った！"}"
  end
end
