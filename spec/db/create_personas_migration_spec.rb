require Rails.root.join("db/migrate/20261123000000_create_personas")

RSpec.describe CreatePersonas do
  def insert_initial
    ActiveRecord::Migration.suppress_messages { described_class.new.send(:insert_initial_personas) }
  end

  it "表が空なら db/seeds/personas.yml の 8 人を並び順のまま、全員有効で入れる" do
    insert_initial

    expect(Persona.enabled.map(&:slug)).to eq(%w[oda-nobunaga joseph-stalin mao-zedong shuzo-matsuoka otto-von-bismarck genghis-khan donald-trump margaret-thatcher])
    expect(Persona.all).to all(be_valid)
    expect(Persona.find_by!(slug: "oda-nobunaga").system_prompt).to include("あなたは織田信長だ。")
  end

  it "すでに人物がいれば何も入れない（入れた後の書き換えを初期値で戻さない）" do
    create(:persona, slug: "oda-nobunaga", name: "書き換えた信長")

    expect { insert_initial }.not_to change(Persona, :count)
    expect(Persona.sole.name).to eq("書き換えた信長")
  end
end
