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

  it "名前・肩書き・色・人物像・口調の指示は前後の空白を落とす（中の改行は残す）" do
    persona = create(:persona, name: " 織田信長\n", system_prompt: "\n一行目\n二行目\n ")

    expect(persona).to have_attributes(name: "織田信長", system_prompt: "一行目\n二行目")
  end

  it "slug の重複は DB の一意制約でも止める" do
    create(:persona, slug: "oda-nobunaga")

    expect { build(:persona, slug: "oda-nobunaga").save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "slug を渡さずに作ると persona- と英小文字の乱数を振り、渡した slug はそのまま使う" do
    made = create(:persona, slug: nil)
    given = create(:persona, slug: "oda-nobunaga")

    expect(made.slug).to match(/\Apersona-[a-z]{8}\z/)
    expect(made).to be_valid
    expect(given.slug).to eq("oda-nobunaga")
  end

  it "position を渡さずに作ると今の最後の後ろに並び、表が空なら先頭になる。明示した 0 はそのまま使う" do
    expect(described_class.create!(attributes_for(:persona).except(:position)).position).to eq(0)

    create(:persona, position: 5)
    create(:persona, position: 2)

    expect(described_class.create!(attributes_for(:persona).except(:position)).position).to eq(6)
    expect(create(:persona, position: 0).position).to eq(0)
  end

  it "色を渡さずに作ると灰色 #6B7280 になる" do
    expect(described_class.new.color).to eq("#6B7280")
    expect(create(:persona, color: "#112233").color).to eq("#112233")
  end
end
