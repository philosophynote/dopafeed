# 設定と API キーは対で揃えないと configured? が偽になり判定が積まれないので、判定を使う例にはまとめて差し込む。
# yml の実物の鍵の名前は spec/lib/dopamine_spec.rb が見る。
module JudgmentHelper
  SETTINGS = { model: "typesafe/jev-1.14", input_chars: 2000, timeout_seconds: 5 }.freeze
  ENDPOINT = "https://openrouter.ai/api/alpha/decisions".freeze

  def judgment_response(scores, cost: 0.0003)
    answers = scores.transform_values do |score|
      levels = ArticleRarityJudge.question_definitions.values.first.criteria.size
      { score: score, legend: (0...levels).to_h { |i| [ i.to_s, "段 #{i}" ] }, probabilities: (0...levels).to_h { |i| [ i.to_s, 1.0 / levels ] }, confidence: 0.8 }
    end
    { model: SETTINGS[:model], usage: { input_tokens: 1200, output_tokens: 0, cost: cost }, answers: answers }.to_json
  end
end

RSpec.shared_context "判定が設定済み" do
  include JudgmentHelper

  before { allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(judgment: JudgmentHelper::SETTINGS)) }

  around { |example| with_env("OPENROUTER_API_KEY" => "test-key") { example.run } }
end
