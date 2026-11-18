module RadarChartHelper
  RADIUS = 60
  LABEL_GAP = 9

  # @param points [Array<Integer>] 軸ごとの点。最初の軸が真上で、以後は時計回り
  # @return [Array<Array(Float, Float)>] 中心を原点にした頂点
  def radar_vertices(points)
    points.each_with_index.map { |point, i| radar_point(i, points.size, RADIUS * point.to_f / ArticleJudgment::LEVELS) }
  end

  # 左右の軸で中央揃えにすると、長い名前が図にかぶる。
  #
  # @return [Array<Hash>] x, y, anchor（text-anchor の値）
  def radar_axes(points)
    points.each_index.map do |i|
      x, y = radar_point(i, points.size, RADIUS + LABEL_GAP)
      { x: x, y: y, anchor: { 0 => "middle", 1 => "start", -1 => "end" }.fetch(x <=> 0) }
    end
  end

  def radar_polygon(points)
    radar_vertices(points).map { |vertex| vertex.join(",") }.join(" ")
  end

  private

  # 丸めた -0.0 は、属性に書くと "-0.0" になる。
  def radar_point(index, count, distance)
    angle = 2 * Math::PI * index / count
    [ Math.sin(angle), -Math.cos(angle) ].map { |unit| (unit * distance).round(1) + 0.0 }
  end
end
