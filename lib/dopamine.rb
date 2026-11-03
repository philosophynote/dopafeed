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
end
