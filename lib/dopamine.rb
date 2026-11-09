# config/dopamine.yml を読む入口。数字はここを通して yml から取る（コードに埋めない）。
# config_for はキャッシュしないので呼ぶたびに YAML を読む。一人用の頻度なら問題にならない。
# 値を変えるのは nao だけ（AGENTS.md）
module Dopamine
  # @return [ActiveSupport::OrderedOptions] dopamine.yml の内容。入れ子は Hash なので dig で辿る
  def self.settings
    Rails.application.config_for(:dopamine)
  end

  # カードの枠の希少度の段。yml の順（低い段から頂点へ）
  #
  # @return [Array<Hash>] name / probability
  def self.rarities
    settings.dig(:cards, :rarities)
  end

  # 希少度の名前。{Reading#tier} の取りうる値
  #
  # @return [Array<String>] cards.rarities の name を yml の順で（common / rare / jackpot）
  def self.rarity_names
    rarities.map { |rarity| rarity[:name] }
  end

  # 名前で引いた段（name / probability）。無い名前なら nil
  def self.rarity(name)
    rarities.find { |rarity| rarity[:name] == name }
  end

  # 一番低い段（通常）。yml の最初の段で決める（{top_rarity} と対にして、並び順を約束にする）
  #
  # @return [Hash] name / probability
  def self.base_rarity
    rarities.first
  end

  # 頂点の段（金）。yml の最後の段で決める。
  # 名前で引くと yml の綴りに縛られ、確率で引くと同率の段が増えたときに揺れるため、並び順を約束にする
  #
  # @return [Hash] name / probability
  def self.top_rarity
    rarities.last
  end

  # 通知の時刻（push.digest_at / push.streak_warning_at）を "HH:MM" で。鍵が無ければ nil。
  # 引用符を忘れた 07:30 は YAML が六十進数（27000 秒）に読むので、その形も同じ表記に戻す（27000 のまま見せない）
  #
  # @param key [Symbol] :digest_at か :streak_warning_at
  # @return [String, nil]
  def self.clock_time(key)
    value = settings.dig(:push, key)
    case value
    when Integer then format("%02d:%02d", value / 3600, value % 3600 / 60)
    when String then value
    end
  end
end
