RSpec.describe "Feeds", type: :system do
  def swipe(dx, dy = 0, ending = "pointerup")
    page.execute_script(<<~JS, find("[data-feed]").native, dx, dy, ending)
      const [row, dx, dy, ending] = arguments, r = row.getBoundingClientRect()
      for (const [type, x, y] of [["pointerdown", 0, 0], ["pointermove", 0, 0], ["pointermove", 0, 1], ["pointermove", dx, dy], [ending, dx, dy]]) {
        row.dispatchEvent(new PointerEvent(type, { bubbles: true, pointerId: 7, isPrimary: true,
          button: 0, clientX: r.left + r.width / 2 + x, clientY: r.top + 20 + y }))
      }
    JS
  end

  it "購読に移動し、390×844 で横スクロールと小さいタップ領域がない" do
    feed = create(:feed, title: "Ruby Weekly", url: "https://example.com/" + "long-path/" * 15, last_error: "サーバーエラー (HTTP 503)")
    create(:article, :read, feed: feed)
    create(:article, feed: feed)
    create(:feed, title: "Zenn", last_fetched_at: 3.minutes.ago)
    sign_in
    click_on "購読"
    expect(page).to have_css("h1", text: "購読 (2)")
    expect(page).to have_button("フィードを追加", disabled: true)
    expect(page).to have_text("0件・未読 0")
    expect(viewport_width).to eq(390)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    expect(page.evaluate_script("Array.from(document.querySelectorAll('a, button')).every(e => { const r = e.getBoundingClientRect(); return r.width >= 44 && r.height >= 44 })")).to be(true)
    screenshot!("list")
    find("nav").find_link(href: root_path).click
    expect(page).to have_current_path(root_path)
  end

  it "削除確認で影響を伝え、キャンセルなら残し、承認なら空状態になる" do
    feed = create(:feed, title: "消す購読")
    sign_in
    click_on "購読"
    dismiss_confirm(/累計 XP・読了数・連続日数/) { click_on "削除" }
    expect(page).to have_text("消す購読")
    expect(Feed.exists?(feed.id)).to be(true)
    accept_confirm { click_on "削除" }
    expect(page).to have_text("購読中のフィードはありません")
    expect(Feed.exists?(feed.id)).to be(false)
  end

  it "右・縦・短いスワイプと中断では残り、左スワイプは確認を経て削除する" do
    feed = create(:feed, title: "スワイプする購読")
    sign_in
    click_on "購読"
    swipe(180)
    swipe(-20, 160)
    swipe(-10)
    swipe(-180, 0, "pointercancel")
    expect(page).to have_text("スワイプする購読")
    dismiss_confirm { swipe(-180) }
    expect(Feed.exists?(feed.id)).to be(true)
    accept_confirm { swipe(-180) }
    expect(page).to have_text("購読中のフィードはありません")
  end
end
