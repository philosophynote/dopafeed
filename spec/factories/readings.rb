# 読了（1 記事 1 行）。既定は「読む」を押して開いただけ。完読は :completed。
# :completed の xp / combo_multiplier は「確定済みの任意の値」。yml の倍率から導いた値ではない（計算は Unit 5 の範囲）
FactoryBot.define do
  factory :reading do
    article
    tier { Dopamine.tier_names.first }
    opened_at { Time.zone.local(2026, 10, 6, 8) }

    trait :completed do
      returned_at { opened_at + 4.minutes + 12.seconds }
      completed_at { opened_at + 4.minutes + 12.seconds }
      combo_multiplier { 1.0 }
      xp { 10 }
    end
  end
end
