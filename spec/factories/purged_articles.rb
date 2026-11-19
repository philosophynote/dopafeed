FactoryBot.define do
  factory :purged_article do
    feed
    sequence(:guid) { |n| "purged-#{n}" }
    sequence(:url) { |n| "https://fixtures.example.com/purged/#{n}" }
    reason { "unread" }
    purged_at { Time.zone.local(2026, 10, 10, 12) }
  end
end
