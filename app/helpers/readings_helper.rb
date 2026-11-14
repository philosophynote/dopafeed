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

  def card_name(name)
    name == Dopamine.top_rarity[:name] ? "#{rarity_label(name)}のカード" : "#{rarity_label(name)}カード"
  end

  def base_rarity?(name)
    name == Dopamine.base_rarity[:name]
  end

  def rarity_tone(name, base:)
    if name == Dopamine.top_rarity[:name] then "bg-amber-400 text-amber-950"
    elsif base_rarity?(name) then base
    else "bg-orange-500 text-white"
    end
  end

  # 通常の出目は鳴らさない（毎回鳴ると、上の段が出たときに効かなくなる）
  def rarity_cue(name)
    if name == Dopamine.top_rarity[:name] then "gold"
    elsif !base_rarity?(name) then "rare"
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

  # 段が上がるほど派手な音にする。金の全画面の開封が出るときは、そちらのファンファーレだけにする
  def highlight_cue(highlights)
    { small: "card", medium: "combo", large: "highlight", huge: "fanfare" }.fetch(highlights.tier)
  end

  def rarity_percent(rarity)
    number_with_precision(rarity[:probability] * 100, precision: 1, strip_insignificant_zeros: true)
  end

  def reveal_seconds
    number_with_precision(Dopamine.settings.dig(:cards, :reveal_duration_ms) / 1000.0, precision: 1)
  end

  def daily_goal_line(summary)
    rest = summary.remaining
    "今日のゴール #{summary.count} / #{summary.goal} ・ #{rest.positive? ? "あと #{rest} 本で宝箱" : "読み切った！"}"
  end
end
