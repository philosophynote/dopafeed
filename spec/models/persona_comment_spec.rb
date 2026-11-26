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

  it "本文の無い行は書いている途中、失敗の時刻があれば失敗、本文があれば書き上がり" do
    writing = article.persona_comments.create!(persona_id: "oda-nobunaga")
    expect(writing).to be_valid
    expect(writing.state).to eq(:writing)

    writing.update!(failed_at: Time.current, error: "応答の形式が不正")
    expect(writing.state).to eq(:failed)

    writing.update!(body: "書けた", failed_at: nil, error: nil)
    expect(writing.state).to eq(:written)
    expect(described_class.written).to eq([ writing ])
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

  describe ".lineup（欄に並べる組）" do
    before { %w[joseph-stalin mao-zedong].each { |slug| create(:persona, slug:) } }

    it "最後に一緒に並べた行（shown_at が最も新しい行）を作った順に返し、外した人は除く" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(comments: { personas_shown: 2 }))
      old = article.persona_comments.create!(persona_id: "oda-nobunaga", body: "x", shown_at: 1.hour.ago)
      now = Time.current
      first = article.persona_comments.create!(persona_id: "joseph-stalin", shown_at: now)
      second = article.persona_comments.create!(persona_id: "mao-zedong", body: "y", shown_at: now)

      expect(described_class.lineup(article)).to eq([ first, second ])
      Persona.find_by!(slug: "joseph-stalin").update!(enabled: false)
      expect(described_class.lineup(article)).to eq([ second, old ])
      expect(old.reload.shown_at).to be < now
    end

    it "組の人を外して足りなくなったら、組の外の有効な行から作った順に補う（再読込でも同じ組）" do
      create(:persona, slug: "genghis-khan")
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(comments: { personas_shown: 2 }))
      extra = %w[mao-zedong genghis-khan].map { |slug| article.persona_comments.create!(persona_id: slug, body: "x") }
      now = Time.current
      kept = article.persona_comments.create!(persona_id: "oda-nobunaga", shown_at: now)
      article.persona_comments.create!(persona_id: "joseph-stalin", shown_at: now)
      Persona.find_by!(slug: "joseph-stalin").update!(enabled: false)

      expect(described_class.lineup(article)).to eq([ kept, extra.first ])
    end

    it "並べた記録が無ければ（記録を始める前の行）、yml の人数を選んで返す" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(comments: { personas_shown: 2 }))
      %w[oda-nobunaga joseph-stalin mao-zedong].each { |slug| article.persona_comments.create!(persona_id: slug, body: "x") }

      lineup = described_class.lineup(article)
      expect(lineup.size).to eq(2)
      3.times { expect(described_class.lineup(article)).to eq(lineup) }
    end
  end
end
