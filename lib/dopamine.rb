# config/dopamine.yml を読む唯一の入口。数字はここを通して yml から取る（コードに埋めない）。
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
