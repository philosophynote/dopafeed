# 読了（1 記事 1 行）。既定は「読む」を押して開いただけ。完読（= 図鑑のカード）は :completed。
# 希少度 tier は既定で一番低い段。頂点は :jackpot
FactoryBot.define do
  factory :reading do
    article
    tier { Dopamine.rarity_names.first }
    opened_at { Time.zone.local(2026, 10, 6, 8) }

    trait :completed do
      returned_at { opened_at + 4.minutes + 12.seconds }
      completed_at { opened_at + 4.minutes + 12.seconds }
    end

    trait :rare do
      tier { Dopamine.rarity_names.second }
    end

    trait :jackpot do
      tier { Dopamine.top_rarity[:name] }
    end
  end
end
