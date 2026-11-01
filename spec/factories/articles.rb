# 記事。既定で 3 行要約つき、未読・未保存。
# :unsummarized 要約前 / :liked いいね / :bookmarked 保存 / :opened 開いただけ / :read 完読
# :opened / :read は after(:create) で Reading を作るので create 専用（build では Reading が付かない）
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

    trait :liked do
      liked_at { Time.zone.local(2026, 10, 4, 12) }
    end

    trait :bookmarked do
      bookmarked_at { Time.zone.local(2026, 10, 4, 13) }
    end

    trait :opened do
      after(:create) { |article| create(:reading, article: article) }
    end

    trait :read do
      after(:create) { |article| create(:reading, :completed, article: article) }
    end
  end
end
