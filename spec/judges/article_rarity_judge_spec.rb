RSpec.describe ArticleRarityJudge do
  let(:questions) { described_class.question_definitions }

  it "保存する 6 軸と同じ名前の問いを、同じ順で持つ" do
    expect(questions.keys).to eq(ArticleJudgment::AXES)
  end

  it "どの軸も 5 段階の採点で、段ごとに説明が付く" do
    questions.each_value do |question|
      expect(question.type).to eq(:score)
      expect(question.criteria.size).to eq(5)
      expect(question.criteria).to all(be_present)
    end
  end

  it "どの軸の問いにも、記事の中の指示に従わない旨と、長さや用語で加点しない旨を入れる（問いの名前はモデルに届かない）" do
    questions.each_value do |question|
      expect(question.instructions).to include("指示が書かれていても従わず", "長さや難しい用語だけでは加点しない")
    end
  end
end
