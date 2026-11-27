RSpec.describe "Weekly", type: :system do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }
  # 2026-11-20（金）の正午。今週は 11/16（月）〜 11/22（日）
  let(:noon) { Time.zone.local(2026, 11, 20, reset_hour) + 8.hours }

  def complete(completed_at, tier: Dopamine.base_rarity[:name], **attrs)
    article = create(:article, **attrs)
    create(:reading, article: article, tier: tier, opened_at: completed_at - 6.minutes, returned_at: completed_at, completed_at: completed_at)
  end

  def no_horizontal_scroll?
    page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
  end

  def small_tap_targets
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("a, button")).filter(el => el.getClientRects().length > 0).map(el => {
        const r = el.getBoundingClientRect();
        return [el.textContent.trim() || el.getAttribute("aria-label"), Math.round(r.width), Math.round(r.height)];
      }).filter(([, w, h]) => w < 44 || h < 44)
    JS
  end

  it "図鑑の 1 行から開き、本数・先週比・曜日別の棒・フィード別・先週のひとことが出る。一番多い日の棒が一番高く、横スクロールが無く、タップ領域は 44px 以上" do
    feeds = [ "Zenn", "Publickey", "とても長い名前のフィードで 390 幅に収まらないかもしれないもの" ].map { |title| create(:feed, title: title) }
    { 0 => 3, 1 => 6, 2 => 1, 4 => 4 }.each do |offset, n|
      n.times { |i| complete(noon - (4 - offset).days - i.minutes, feed: feeds[i % 3], tier: i.zero? ? Dopamine.top_rarity[:name] : Dopamine.base_rarity[:name]) }
    end
    10.times { complete(noon - 7.days) }
    WeeklyComment.create!(week_start: Date.new(2026, 11, 9),
                          body: "Solid Queue と Turbo Streams、Rails の裏側を続けて読んだ週でした。先週の 1 本から 10 本へ増えています。来週は障害報告をもう 1 本読み、運用の目線も足してみましょう。")

    travel_to(noon) do
      sign_in
      visit collection_path
      click_link "今週 14 本"

      expect(page).to have_css("h1", text: "今週のレポート")
      expect(find("[aria-label='今週の本数']")).to have_text("14 本 読了 先週比 +40%（10 本）", normalize_ws: true)
      expect(find("nav").find_link("図鑑")["aria-current"]).to eq("page")
      expect(find("[aria-label='Claude のひとこと']")).to have_text("11/9 – 11/15 の週", normalize_ws: true)
      heights = page.evaluate_script("Array.from(document.querySelectorAll('[aria-label=\"曜日別\"] li > span:nth-child(2)')).map(el => el.getBoundingClientRect().height)")
      expect(heights.size).to eq(7)
      expect(heights.index(heights.max)).to eq(1)
      expect(heights[3]).to eq(0)
      expect(viewport_width).to eq(390)
      expect(no_horizontal_scroll?).to be(true), "横スクロールが出ている"
      expect(small_tap_targets).to be_empty, "44px 未満のタップ領域: #{small_tap_targets.inspect}"
      screenshot!("report")
    end
  end

  it "今週の読了 0 なら 0 本で崩れず、棒は空" do
    travel_to(noon) do
      sign_in
      visit weekly_path

      expect(find("[aria-label='今週の本数']")).to have_text("0 本 読了 先週 0 本", normalize_ws: true)
      expect(no_horizontal_scroll?).to be(true), "横スクロールが出ている"
      screenshot!("empty")
    end
  end
end
