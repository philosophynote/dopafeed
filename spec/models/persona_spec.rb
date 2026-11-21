RSpec.describe Persona do
  it "config/personas.yml の 8 人を並び順のまま読む" do
    expect(described_class.all.map(&:name)).to eq(%w[織田信長 ヨシフ・スターリン 毛沢東 ナポレオン・ボナパルト ガイウス・ユリウス・カエサル チンギス・ハン 西郷隆盛 スティーブ・ジョブズ])
  end

  it "id は英小文字とハイフンで重ならず、色は #RRGGBB、名前・肩書き・人物像・口調の指示はどれも空でない" do
    personas = described_class.all

    expect(personas.map(&:id)).to all(match(/\A[a-z]+(-[a-z]+)*\z/))
    expect(personas.map(&:id).uniq.size).to eq(personas.size)
    expect(personas.map(&:color)).to all(match(/\A#\h{6}\z/))
    personas.each do |persona|
      expect([ persona.name, persona.title, persona.description, persona.system_prompt ]).to all(be_present), persona.id
    end
  end

  it "id で引ける。無い id は nil" do
    expect(described_class.find("napoleon-bonaparte").name).to eq("ナポレオン・ボナパルト")
    expect(described_class.find("elon-musk")).to be_nil
  end
end
