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
    name == Dopamine.top_rarity[:name] ? "bg-amber-400 text-amber-950" : middle_rarity_style(name, MIDDLE_TONES) || base
  end

  # 版の入れ替わりの間に古い版が書いた名前（yml に無い）でも落とさず、一番下の段と同じに扱う。
  #
  # @return [String, nil] 間の段でなければ nil
  def middle_rarity_style(name, styles)
    position = Dopamine.rarity_names.index(name)
    styles.fetch(position - 1, styles.last) if position&.positive? && name != Dopamine.top_rarity[:name]
  end

  # 一番下の段は鳴らさない（毎回鳴ると、上の段が出たときに効かなくなる）
  def rarity_cue(name)
    if name == Dopamine.top_rarity[:name] then "gold"
    elsif middle_rarity_style(name, [ "rare" ]) then "rare"
    end
  end

  # 1 周だけだと頂点の手前で止まるとき回った感じが出ないので、段を 2 周させてから止める
  def reel_labels(tier)
    names = Dopamine.rarity_names
    (names * 2 + names.take(names.index(tier).to_i)).map { |name| rarity_label(name) }
  end

  # 判定を待つ間は段を回し続ける。最後に先頭の段をもう一度積み、継ぎ目なく繰り返す
  def pending_reel_labels
    names = Dopamine.rarity_names
    (names + names.take(1)).map { |name| rarity_label(name) }
  end

  # 枠が決まった後に届いた判定や、境界を変える前の判定は、枠と段が食い違う。その点を添えると「24 点 ノーマル」になる。
  #
  # @return [String, nil] 枠の根拠。点に依らず一番下の段に決まった行は、判定できなかったと添える
  def judgment_note(reading)
    judgment = reading.article.judgment
    if reading.tier.nil? then "判定中"
    elsif judgment&.judged? && judgment.tier == reading.tier then "#{judgment.total} 点"
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
