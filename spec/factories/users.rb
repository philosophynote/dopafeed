# ユーザーは本番では 1 人（ADR 0005）。spec では必要な数だけ作る
FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    password { "password" }
  end
end
