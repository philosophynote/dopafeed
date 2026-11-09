# :completed の xp / combo_multiplier は確定済みの任意値で、yml の計算結果ではない。
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
