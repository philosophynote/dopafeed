# 記事。既定で 3 行要約つき、未読・未保存。
# :unsummarized 要約前 / :awaiting_summary 本文取得を試した後の要約待ち / :summary_failed 要約に失敗 / :liked いいね / :bookmarked 保存 / :dismissed 興味なし / :opened 開いただけ / :read 完読
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

    trait :awaiting_summary do
      summary { nil }
      content { "<h1>見出し</h1><p>最初の段落。</p><p>二つ目の<strong>段落</strong>。</p>" }
      content_fetched_at { Time.zone.local(2026, 10, 1, 10) }
    end

    trait :summary_failed do
      awaiting_summary
      summary_failed_at { Time.zone.local(2026, 10, 1, 11) }
      summary_error { "応答の形式が不正" }
    end

    trait :liked do
      liked_at { Time.zone.local(2026, 10, 4, 12) }
    end

    trait :bookmarked do
      bookmarked_at { Time.zone.local(2026, 10, 4, 13) }
    end

    trait :dismissed do
      dismissed_at { Time.zone.local(2026, 10, 5, 12) }
    end

    trait :opened do
      after(:create) { |article| create(:reading, article: article) }
    end

    trait :read do
      after(:create) { |article| create(:reading, :completed, article: article) }
    end
  end
end
