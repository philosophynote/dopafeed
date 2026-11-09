FactoryBot.define do
  factory :feed do
    sequence(:title) { |n| "Feed #{n}" }
    sequence(:url) { |n| "https://fixtures.example.com/feed#{n}/feed.xml" }
    sequence(:site_url) { |n| "https://fixtures.example.com/feed#{n}" }
  end
end
