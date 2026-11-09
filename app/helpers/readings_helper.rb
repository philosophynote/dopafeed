module ReadingsHelper
  def dwell_in_words(seconds)
    return "" if seconds.nil?

    minutes, rest = seconds.divmod(60)
    minutes.positive? ? "#{minutes}分#{rest}秒" : "#{rest}秒"
  end

  # 保存に使う出目の英字名を、表示の翻訳に依存させない。
  def tier_label(name)
    I18n.t("dopamine.tiers.#{name}", locale: :ja, default: name)
  end

  def tier_percent(tier)
    number_with_precision(tier[:probability] * 100, precision: 1, strip_insignificant_zeros: true)
  end

  def roulette_seconds
    number_with_precision(Dopamine.settings.dig(:xp, :roulette_duration_ms) / 1000.0, precision: 1)
  end

  def daily_goal_line(summary)
    rest = summary.remaining
    "今日のゴール #{summary.count} / #{summary.goal} ・ #{rest.positive? ? "あと #{rest} 本で宝箱" : "読み切った！"}"
  end
end
