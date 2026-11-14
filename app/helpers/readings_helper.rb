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
