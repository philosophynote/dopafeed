# 記事。既定で 3 行要約つき。要約前の記事は :unsummarized
FactoryBot.define do
  factory :article do
    feed
    sequence(:title) { |n| "記事 #{n}" }
    sequence(:url) { |n| "https://fixtures.example.com/articles/#{n}" }
    summary { "・1 行目\n・2 行目\n・3 行目" }
    sequence(:published_at) { |n| Time.zone.local(2026, 10, 1, 9) + n.hours }

    trait :unsummarized do
      summary { nil }
    end
  end
end
