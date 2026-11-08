# 図鑑を 390×844 で開く。タブバーからの動線、3 列のグリッド、見た目の崩れ（横スクロール・タップ領域）、空状態
RSpec.describe "Collection", type: :system do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }
  let(:gold) { Dopamine.top_rarity[:name] }
  let(:rare) { Dopamine.rarity_names.second }

  def card(title:, completed_at:, tier: Dopamine.base_rarity[:name], **attrs)
    article = create(:article, title: title, **attrs)
    create(:reading, article: article, tier: tier, opened_at: completed_at - 4.minutes, returned_at: completed_at, completed_at: completed_at)
  end

  it "タブバーの「図鑑」から開き、30 枚が日ごとに 3 列で並ぶ。金とレアは枠の色で分かり、横スクロールが無く、タップ領域は 44px 以上" do
    feeds = Array.new(3) { |i| create(:feed, title: "Feed #{i}") }
    now = Time.current
    30.times do |i|
      tier = if i == 1 then gold elsif (i % 7).zero? then rare else Dopamine.base_rarity[:name] end
      card(title: "#{i + 1} 枚目の、390 幅の 3 列で 3 行に折り返されるくらい長い見出し", completed_at: now - (i * 5).hours - 1.minute,
           tier: tier, feed: feeds[i % 3], image_url: i.even? ? "/icon.png" : nil)
    end
    create(:article, title: "Main の未読")
    sign_in

    find("nav").click_link("図鑑")

    expect(page).to have_css("h1", text: "図鑑")
    expect(page).to have_text("30 枚", normalize_ws: true)
    expect(page).to have_css("li[data-tier]", count: 30)
    expect(page).to have_css("li[data-tier='#{gold}']", count: 1)
    expect(page.first("section[data-day] h2").text).to eq("今日")
    expect(find("nav").find_link("図鑑")["aria-current"]).to eq("page")
    expect(viewport_width).to eq(390)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    # 3 列: 最初の束の先頭 3 枚は同じ高さに並び、4 枚目は下の行
    tops = page.evaluate_script("Array.from(document.querySelectorAll('section[data-day] li')).slice(0, 4).map(li => Math.round(li.getBoundingClientRect().top))")
    expect(tops[0..2].uniq.size).to eq(1)
    expect(tops[3]).to be > tops[0]
    small = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("a, button")).filter(el => el.getClientRects().length > 0).map(el => {
        const r = el.getBoundingClientRect();
        return [el.textContent.trim() || el.getAttribute("aria-label"), Math.round(r.width), Math.round(r.height)];
      }).filter(([, w, h]) => w < 44 || h < 44)
    JS
    expect(small).to be_empty, "44px 未満のタップ領域: #{small.inspect}"
    screenshot!("cards")
  end

  it "0 枚なら空状態" do
    sign_in
    visit collection_path

    expect(page).to have_css("h1", text: "図鑑")
    expect(page).to have_text("まだカードはありません。")
    expect(page).to have_no_css("li[data-tier]")
    screenshot!("empty")
  end
end
