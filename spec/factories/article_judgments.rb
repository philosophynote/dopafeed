FactoryBot.define do
  factory :article_judgment do
    article
    originality { 3.2 }
    depth { 2.6 }
    practicality { 3.0 }
    evidence { 1.4 }
    insight { 2.5 }
    applicability { 0.4 }
    model { "jev-latest" }
    input_tokens { 1200 }
    cost { 0.0003 }
    judged_at { Time.zone.local(2026, 10, 6, 8) }

    trait :failed do
      ArticleJudgment::AXES.each { |axis| send(axis) { nil } }
      model { nil }
      input_tokens { nil }
      cost { nil }
      judged_at { nil }
      failed_at { Time.zone.local(2026, 10, 6, 8) }
      error { "判定として読めない応答 (HTTP 200)" }
    end
  end
end
