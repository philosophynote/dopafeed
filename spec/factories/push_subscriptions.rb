FactoryBot.define do
  factory :push_subscription do
    sequence(:endpoint) { |n| "https://push.example.com/sub/#{n}" }
    p256dh { "BFakeP256dhKey" }
    auth { "fakeauth" }
    user_agent { "Mozilla/5.0 (iPhone)" }
  end
end
