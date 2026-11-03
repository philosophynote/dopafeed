module ReadingsHelper
  # 滞在時間の表示。秒数だけだと長さが掴めないので分と秒に分ける
  #
  # @param seconds [Integer, nil]
  # @return [String] 例: 4分12秒。戻っていなければ空
  def dwell_in_words(seconds)
    return "" if seconds.nil?

    minutes, rest = seconds.divmod(60)
    minutes.positive? ? "#{minutes}分#{rest}秒" : "#{rest}秒"
  end
end
