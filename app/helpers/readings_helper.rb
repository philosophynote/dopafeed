# ReadDone・Roulette・Jackpot の表示だけの整形。判定と XP はモデルが決め、ここでは数を言葉にするだけ
module ReadingsHelper
  # 滞在時間の表示。秒数だけだと長さが掴めないので分と秒に分ける
  #
  # @return [String] 例: 4分12秒。戻っていなければ空
  def dwell_in_words(seconds)
    return "" if seconds.nil?

    minutes, rest = seconds.divmod(60)
    minutes.positive? ? "#{minutes}分#{rest}秒" : "#{rest}秒"
  end

  # 出目の名前の日本語。yml の name は英字のまま保存に使い、見せる語は locale に置く
  #
  # @return [String] 例: 掘り出し物。訳が無ければ name のまま
  def tier_label(name)
    I18n.t("dopamine.tiers.#{name}", locale: :ja, default: name)
  end

  # 出目の確率を百分率で。0.05 → 5、0.003 → 0.3（整数なら小数を出さない）
  def tier_percent(tier)
    number_with_precision(tier[:probability] * 100, precision: 1, strip_insignificant_zeros: true)
  end

  # ルーレットが止まるまでの秒。yml は ms で持つ
  #
  # @return [String] 例: 0.5
  def roulette_seconds
    number_with_precision(Dopamine.settings.dig(:xp, :roulette_duration_ms) / 1000.0, precision: 1)
  end
end
