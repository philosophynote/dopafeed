# config/dopamine.yml を読む入口。数字はここを通して yml から取る（コードに埋めない）。
# config_for はキャッシュしないので呼ぶたびに YAML を読む。一人用の頻度なら問題にならない。
# 値を変えるのは nao だけ（AGENTS.md）
module Dopamine
  # @return [ActiveSupport::OrderedOptions] dopamine.yml の内容。入れ子は Hash なので dig で辿る
  def self.settings
    Rails.application.config_for(:dopamine)
  end

  # ルーレットの出目の名前。{Reading#tier} の取りうる値
  #
  # @return [Array<String>] xp.tiers の name を yml の順で（common / rare / jackpot）
  def self.tier_names
    settings.dig(:xp, :tiers).map { |tier| tier[:name] }
  end

  # 名前で引いた tier（name / multiplier / probability）。無い名前なら nil
  def self.tier(name)
    settings.dig(:xp, :tiers).find { |tier| tier[:name] == name }
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

  # 抽選の頂点の出目。名前ではなく倍率が最も高い tier で決める。
  # 名前で引くと yml の綴りに縛られ、上に段を足したときに頂点がずれるため
  #
  # @return [Hash] name / multiplier / probability
  def self.jackpot_tier
    settings.dig(:xp, :tiers).max_by { |tier| tier[:multiplier] }
  end
end
