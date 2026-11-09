# 図鑑とカードの見た目だけの整形。希少度の色は {ReadingsHelper#rarity_tone}（帯と区切り）と対で、ここは枠と色地
module CollectionHelper
  # フィードごとの色地。画像の無い記事のカードを、同じフィードなら同じ色にして見分けさせる。
  # 色は固定の数色を id で回す（好みが出たら feeds に列を足す）
  FEED_TONES = %w[bg-sky-600 bg-emerald-600 bg-violet-600 bg-rose-600 bg-amber-600 bg-teal-600 bg-indigo-600 bg-fuchsia-600].freeze

  def feed_tone(feed)
    FEED_TONES[feed.id % FEED_TONES.size]
  end

  # カードの枠の色。頂点は金、間の段は橙、一番低い段は灰。帯より太く見せるのは、並べたときに希少度が一目で分かるように
  def rarity_frame(name)
    if name == Dopamine.top_rarity[:name] then "border-amber-400 shadow-[0_0_0_2px_rgba(251,191,36,0.45)]"
    elsif base_rarity?(name) then "border-gray-200"
    else "border-orange-500"
    end
  end

  # 束の見出し。今日・昨日はその名で、それより前は月日と曜日（年は出さない。年をまたいだら考える）
  #
  # @return [String] 例: 今日 / 昨日 / 11月6日（木）
  def reading_day_label(day, today: ReadingDay.of)
    case today - day
    when 0 then "今日"
    when 1 then "昨日"
    else "#{day.month}月#{day.day}日（#{%w[日 月 火 水 木 金 土][day.wday]}）"
    end
  end
end
