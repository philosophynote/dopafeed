FactoryBot.define do
  factory :persona do
    sequence(:slug) { |n| "persona-#{n.to_s.tr("0-9", "a-j")}" }
    sequence(:name) { |n| "人物 #{n}" }
    title { "肩書き" }
    color { "#123ABC" }
    description { "ひとこと紹介" }
    system_prompt { "あなたは架空の人物だ。" }
    sequence(:position)
  end
end
