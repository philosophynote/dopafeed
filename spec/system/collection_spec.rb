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
    # 今日の束に 4 枚を置くため、読書日の正午に固定する（実時刻だと reset_hour の直後に束が割れる）
    noon = Time.zone.local(2026, 11, 6, reset_hour) + 8.hours
    30.times do |i|
      tier = if i == 1 then gold elsif (i % 7).zero? then rare else Dopamine.base_rarity[:name] end
      card(title: "#{i + 1} 枚目の、390 幅の 3 列で 3 行に折り返されるくらい長い見出し", completed_at: noon - (i * 2).hours - 1.minute,
           tier: tier, feed: feeds[i % 3], image_url: i.even? ? "/icon.png" : nil)
    end
    create(:article, title: "Main の未読")
    travel_to(noon) do
    sign_in

    find("nav").click_link("図鑑")

    expect(page).to have_css("h1", text: "図鑑")
    expect(page).to have_text("30 枚", normalize_ws: true)
    expect(page).to have_css("li[data-tier]", count: 30)
    expect(page).to have_css("li[data-tier='#{gold}']", count: 1)
    expect(page.first("section[data-day] h2").text).to eq("今日")
    expect(page.first("section[data-day]")).to have_css("li[data-tier]", count: 4)
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
  end

  it "4 段と判定中のカードは枠で見分けられ、内訳に判定中の枚数が出て、横スクロールが無い" do
    noon = Time.zone.local(2026, 11, 6, reset_hour) + 8.hours
    [ *Dopamine.rarity_names, nil ].each_with_index do |tier, i|
      card(title: "#{tier || "判定中"} の記事", completed_at: noon - i.minutes, tier: tier)
    end
    travel_to(noon) do
      sign_in
      visit collection_path

      expect(find("[aria-label='内訳']")).to have_text("ノーマル 1 ・ レア 1 ・ S レア 1 ・ SS レア 1 ・ 判定中 1", normalize_ws: true)
      frames = page.evaluate_script("Array.from(document.querySelectorAll('li[data-tier]')).map(li => [ getComputedStyle(li).borderTopStyle, getComputedStyle(li).borderTopColor ])")
      expect(frames.map(&:first)).to eq(%w[solid solid solid solid dashed])
      expect(frames.map(&:last).uniq.size).to eq(5), "枠の色が段ごとに違わない: #{frames.inspect}"
      expect(page).to have_css("li[data-tier=''] [data-rarity-label]", text: "判定中")
      expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
      screenshot!("tiers")
    end
  end

  it "カードを押すと裏が開き、6 軸のレーダーと点が図からはみ出さずに出る。横スクロールが無く、タップ領域は 44px 以上で、図鑑へ戻れる" do
    30.times { |i| card(title: "#{i + 1} 枚目", completed_at: Time.current - 1.minute - i.hours) }
    reading = card(title: "裏を見る、390 幅で 2 行に折り返されるくらい長い見出しの記事", completed_at: Time.current - 2.days, tier: rare)
    create(:article_judgment, article: reading.article, **scores_for(rare))
    sign_in
    visit collection_path

    link = find("li[data-tier='#{rare}'] a")
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", link)
    link.click

    expect(page).to have_current_path(card_path(reading))
    expect(page).to have_css("h1", text: "裏を見る")
    expect(page).to have_css("svg[role='img'] polygon[data-radar-area]")
    expect(page).to have_css("figcaption", text: "合計 #{Dopamine.rarity(rare)[:min_total]} 点")
    clipped = page.evaluate_script(<<~JS)
      (() => {
        const svg = document.querySelector("svg[role='img']")
        const box = svg.getBoundingClientRect()
        return Array.from(svg.querySelectorAll("text")).map((text) => [ text.textContent.trim(), text.getBoundingClientRect() ])
          .filter(([, r]) => r.left < box.left || r.right > box.right || r.top < box.top || r.bottom > box.bottom).map(([ label ]) => label)
      })()
    JS
    expect(clipped).to be_empty, "図の外にはみ出した軸の名前: #{clipped.inspect}"
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    small = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("a, button")).filter(el => el.getClientRects().length > 0).map(el => {
        const r = el.getBoundingClientRect();
        return [el.textContent.trim() || el.getAttribute("aria-label"), Math.round(r.width), Math.round(r.height)];
      }).filter(([, w, h]) => w < 44 || h < 44)
    JS
    expect(small).to be_empty, "44px 未満のタップ領域: #{small.inspect}"
    screenshot!("back")

    click_on "図鑑へ戻る"
    expect(page).to have_current_path(collection_path)
    expect(page).to have_css("li[data-tier='#{rare}']")
    in_view = page.evaluate_script("(() => { const r = document.querySelector(\"li[data-tier='#{rare}']\").getBoundingClientRect(); return r.top >= 0 && r.bottom <= window.innerHeight })()")
    expect(in_view).to be(true), "図鑑の先頭に戻ってしまい、見ていたカードが画面の外"
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
