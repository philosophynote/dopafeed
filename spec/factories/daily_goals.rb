FactoryBot.define do
  factory :daily_goal do
    sequence(:day) { |n| Date.new(2026, 10, 1) + n.days }

    trait :achieved do
      achieved_at { day.in_time_zone + 21.hours }
    end
  end
end
