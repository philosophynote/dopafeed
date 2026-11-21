RSpec.describe PersonaComment do
  let(:article) { create(:article) }

  it "同じ記事に同じ人のコメントは 1 つだけ（DB の一意制約）" do
    article.persona_comments.create!(persona_id: "oda-nobunaga", body: "一つ目")

    expect { described_class.insert_all!([ { article_id: article.id, persona_id: "oda-nobunaga", body: "二つ目" } ]) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "personas.yml に無い人と空の本文は保存しない" do
    expect(article.persona_comments.build(persona_id: "elon-musk", body: "x")).not_to be_valid
    expect(article.persona_comments.build(persona_id: "oda-nobunaga", body: " ")).not_to be_valid
  end

  it "記事を消すとコメントも消える" do
    article.persona_comments.create!(persona_id: "oda-nobunaga", body: "x")

    expect { article.destroy! }.to change(described_class, :count).by(-1)
  end

  it "persona で personas.yml の人物を引ける" do
    expect(described_class.new(persona_id: "margaret-thatcher").persona.name).to eq("マーガレット・サッチャー")
  end
end
