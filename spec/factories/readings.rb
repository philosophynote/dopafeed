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
