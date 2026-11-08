# 読了まわり（Roulette・Jackpot・判定の区切り・カード）の表示だけの整形。判定と希少度はモデルが決め、ここでは数と名前を言葉にするだけ
module ReadingsHelper
  # 滞在時間の表示。秒数だけだと長さが掴めないので分と秒に分ける
  #
  # @return [String] 例: 4分12秒。判定の前なら空
  def dwell_in_words(seconds)
    return "" if seconds.nil?

    minutes, rest = seconds.divmod(60)
    minutes.positive? ? "#{minutes}分#{rest}秒" : "#{rest}秒"
  end

  # 希少度の名前の日本語。yml の name は英字のまま保存に使い、見せる語は locale に置く
  #
  # @return [String] 例: レア。訳が無ければ name のまま
  def rarity_label(name)
    I18n.t("dopamine.rarities.#{name}", locale: :ja, default: name)
  end

  # 完読で手に入るカードの呼び名。頂点だけ「金のカード」と言い、他は希少度の名前を頭に付ける
  #
  # @return [String] 例: 通常カード / レアカード / 金のカード
  def card_name(name)
    name == Dopamine.top_rarity[:name] ? "#{rarity_label(name)}のカード" : "#{rarity_label(name)}カード"
  end

  # 希少度の確率を百分率で。0.05 → 5、0.003 → 0.3（整数なら小数を出さない）
  def rarity_percent(rarity)
    number_with_precision(rarity[:probability] * 100, precision: 1, strip_insignificant_zeros: true)
  end

  # 出目の帯が止まるまでの秒。yml は ms で持つ
  #
  # @return [String] 例: 0.5
  def reveal_seconds
    number_with_precision(Dopamine.settings.dig(:cards, :reveal_duration_ms) / 1000.0, precision: 1)
  end

  # 今日のゴールの進み
  #
  # @return [String] 例: 今日のゴール 4 / 5 ・ あと 1 本で宝箱
  def daily_goal_line(summary)
    rest = summary.remaining
    "今日のゴール #{summary.count} / #{summary.goal} ・ #{rest.positive? ? "あと #{rest} 本で宝箱" : "読み切った！"}"
  end
end
