RSpec.describe Persona do
  it "db/seeds/personas.yml の 8 人はどれも検証を通る" do
    expect(seed_personas.map(&:name)).to eq(%w[織田信長 ヨシフ・スターリン 毛沢東 松岡修造 オットー・フォン・ビスマルク チンギス・ハン ドナルド・J・トランプ マーガレット・サッチャー])
  end

  it "enabled は有効な人だけを並び順（position、同じなら作った順）で返す" do
    early = create(:persona, position: 2)
    top = create(:persona, position: 1)
    create(:persona, position: 1, enabled: false)
    late = create(:persona, position: 2)

    expect(described_class.enabled).to eq([ top, early, late ])
  end

  it "slug は英小文字とハイフンで重ならず、色は #RRGGBB、名前・肩書き・人物像・口調の指示はどれも空にできない" do
    create(:persona, slug: "oda-nobunaga")

    expect(build(:persona, slug: "oda-nobunaga")).not_to be_valid
    expect(build(:persona, slug: "Oda_Nobunaga")).not_to be_valid
    expect(build(:persona, slug: "oda-")).not_to be_valid
    expect(build(:persona, color: "red")).not_to be_valid
    expect(build(:persona, color: "#12345G")).not_to be_valid
    %i[name title description system_prompt].each do |attr|
      expect(build(:persona, attr => " ")).not_to be_valid, attr.to_s
    end
  end

  it "slug の重複は DB の一意制約でも止める" do
    create(:persona, slug: "oda-nobunaga")

    expect { build(:persona, slug: "oda-nobunaga").save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
