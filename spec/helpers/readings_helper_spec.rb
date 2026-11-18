RSpec.describe ReadingsHelper do
  let(:names) { Dopamine.rarity_names }

  describe "#judgment_note" do
    def reading(tier:, judged_as: nil)
      create(:reading, tier: tier).tap do |reading|
        create(:article_judgment, article: reading.article, **scores_for(judged_as)) if judged_as
      end
    end

    it "判定中なら「判定中」、枠が判定の段と同じなら合計点" do
      expect(helper.judgment_note(reading(tier: nil))).to eq("判定中")
      expect(helper.judgment_note(reading(tier: names.second, judged_as: names.second))).to eq("#{Dopamine.rarity(names.second)[:min_total]} 点")
    end

    it "枠が判定の段と食い違う行には点を出さない（境界と合わない「24 点 ノーマル」を見せない）。判定は届いているので「判定できず」とも言わない" do
      expect(helper.judgment_note(reading(tier: names.first, judged_as: names.second))).to be_nil
      expect(helper.judgment_note(reading(tier: names.last, judged_as: names.second))).to be_nil
    end

    it "判定の無い・失敗した記事が一番下の段に決まった行は「判定できず」" do
      failed = reading(tier: names.first)
      create(:article_judgment, :failed, article: failed.article)

      expect(helper.judgment_note(reading(tier: names.first))).to eq("判定できず")
      expect(helper.judgment_note(failed)).to eq("判定できず")
    end
  end

  it "yml に無い名前の枠は、一番下の段の色で描く（落ちない）" do
    helper.extend(CollectionHelper)

    expect(helper.rarity_tone("common", base: "bg-gray-200")).to eq("bg-gray-200")
    expect(helper.rarity_frame("common")).to eq(helper.rarity_frame(names.first))
    expect(helper.rarity_cue("common")).to be_nil
  end
end
