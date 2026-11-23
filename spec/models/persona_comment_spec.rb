RSpec.describe PersonaComment do
  let(:article) { create(:article) }

  before { create(:persona, slug: "oda-nobunaga", name: "織田信長") }

  it "同じ記事に同じ人のコメントは 1 つだけ（DB の一意制約）" do
    article.persona_comments.create!(persona_id: "oda-nobunaga", body: "一つ目")

    expect { described_class.insert_all!([ { article_id: article.id, persona_id: "oda-nobunaga", body: "二つ目" } ]) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "人物の表に無い人と空の本文は保存しない" do
    expect(article.persona_comments.build(persona_id: "elon-musk", body: "x")).not_to be_valid
    expect(article.persona_comments.build(persona_id: "oda-nobunaga", body: " ")).not_to be_valid
  end

  it "記事を消すとコメントも消える" do
    article.persona_comments.create!(persona_id: "oda-nobunaga", body: "x")

    expect { article.destroy! }.to change(described_class, :count).by(-1)
  end

  it "persona_id の slug で人物を引ける。無効にした人でも引け、コメントは残る" do
    comment = article.persona_comments.create!(persona_id: "oda-nobunaga", body: "x")
    Persona.find_by!(slug: "oda-nobunaga").update!(enabled: false)

    expect(comment.reload.persona.name).to eq("織田信長")
  end
end
