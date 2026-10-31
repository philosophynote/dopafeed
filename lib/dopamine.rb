# config/dopamine.yml を読む入口。数字はここを通して yml から取る（コードに埋めない）。
# Claude::Budget だけは Unit 0 の config_for 直読みのまま（差分を増やさないため。寄せるなら別 PR）。
# config_for はキャッシュしないので呼ぶたびに YAML を読む。一人用の頻度なら問題にならない。
# 値を変えるのは nao だけ（AGENTS.md）。
module Dopamine
  def self.settings
    Rails.application.config_for(:dopamine)
  end

  # ルーレットの出目の名前（common / rare / jackpot）。Reading#tier の取りうる値
  def self.tier_names
    settings.dig(:xp, :tiers).map { |tier| tier[:name] }
  end
end
