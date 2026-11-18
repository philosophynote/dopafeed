RSpec.describe RadarChartHelper do
  let(:levels) { ArticleJudgment::LEVELS }
  let(:radius) { RadarChartHelper::RADIUS }

  it "頂点は最初の軸が真上、以後は時計回り。満点で半径いっぱい、1 点でも中心に潰れない" do
    full = helper.radar_vertices(Array.new(6, levels))
    low = helper.radar_vertices(Array.new(6, 1))

    expect(full.first).to eq([ 0.0, -radius.to_f ])
    expect(full.second.first).to be > 0
    expect(full.second.last).to be < 0
    expect(full.fourth).to eq([ 0.0, radius.to_f ])
    expect(low.first).to eq([ 0.0, -(radius.to_f / levels) ])
  end

  it "軸の名前は、左右の軸では外へ向けて揃え、上下の軸では中央に揃える（図にかぶらない）" do
    anchors = helper.radar_axes(Array.new(6, levels)).map { |axis| axis[:anchor] }

    expect(anchors).to eq(%w[middle start start middle end end])
  end
end
