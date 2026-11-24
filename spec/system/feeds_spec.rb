RSpec.describe "Feeds", type: :system do
  def swipe(dx, dy = 0, ending = "pointerup", on: nil)
    page.execute_script(<<~JS, find("[data-feed]").native, on&.native, dx, dy, ending)
      const [row, origin, dx, dy, ending] = arguments, r = row.getBoundingClientRect()
      for (const [type, x, y] of [["pointerdown", 0, 0], ["pointermove", 0, 0], ["pointermove", 0, 1], ["pointermove", dx, dy], [ending, dx, dy]]) {
        (origin || row).dispatchEvent(new PointerEvent(type, { bubbles: true, pointerId: 7, isPrimary: true,
          button: 0, clientX: r.left + r.width / 2 + x, clientY: r.top + 20 + y }))
      }
    JS
  end

  def menu_of(title)
    find("summary[aria-label='「#{title}」の操作']")
  end

  def menu_open?(title)
    page.evaluate_script("arguments[0].closest('details').open", menu_of(title))
  end

  def visible_targets_are_44px
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('a, button, summary, input:not([type=hidden])'))
        .filter(e => e.checkVisibility())
        .every(e => { const r = e.getBoundingClientRect(); return r.width >= 44 && r.height >= 44 })
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
    expect(page).to have_link("フィードを追加", href: new_feed_path)
    expect(find("[data-feed]", text: "Zenn")).to have_text("0件").and have_text("未読 0")
    expect(find("[data-feed]", text: "Ruby Weekly")).to have_text("2件").and have_text("未読 1")
    unread_right_edges = page.evaluate_script("Array.from(document.querySelectorAll('[data-unread]')).map(e => Math.round(e.getBoundingClientRect().right))")
    expect(unread_right_edges.size).to eq(2)
    expect(unread_right_edges.uniq.size).to eq(1)
    expect(viewport_width).to eq(390)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    expect(visible_targets_are_44px).to be(true)
    screenshot!("list")

    menu_of("Zenn").click
    expect(page).to have_link("名前を変更", visible: true)
    expect(visible_targets_are_44px).to be(true)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    last_row_items_on_top = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('[data-feed]:last-of-type details[open] [role=menu] a, [data-feed]:last-of-type details[open] [role=menu] button')).map(e => {
        const r = e.getBoundingClientRect()
        return e.contains(document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2))
      })
    JS
    expect(last_row_items_on_top).to eq([ true, true ])
    screenshot!("menu-open")
    menu_of("Zenn").click
    expect(menu_open?("Zenn")).to be(false)
    find("nav").find_link(href: root_path).click
    expect(page).to have_current_path(root_path)
  end

  it "削除確認で影響を伝え、キャンセルなら残し、承認なら空状態になる" do
    feed = create(:feed, title: "消す購読")
    sign_in
    click_on "購読"
    menu_of("消す購読").click
    dismiss_confirm(/図鑑のカード・読了数・連続日数/) { click_on "削除" }
    expect(page).to have_text("消す購読")
    expect(Feed.exists?(feed.id)).to be(true)
    expect(menu_open?("消す購読")).to be(false)
    menu_of("消す購読").click
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
    swipe(-180, on: menu_of("スワイプする購読"))
    expect(page).to have_text("スワイプする購読")
    dismiss_confirm { swipe(-180) }
    expect(Feed.exists?(feed.id)).to be(true)
    expect(menu_open?("スワイプする購読")).to be(false)
    accept_confirm { swipe(-180) }
    expect(page).to have_text("購読中のフィードはありません")
  end

  it "名前を変更すると行と Main の名前が替わる。「やめる」では替わらず、空白だけなら赤字で残す" do
    feed = create(:feed, title: "Zenn のトレンド", url: "https://example.com/" + "long-path/" * 15)
    create(:article, feed: feed, title: "記事 A")
    sign_in
    click_on "購読"

    menu_of("Zenn のトレンド").click
    click_on "名前を変更"
    expect(page).to have_field("名前", with: "Zenn のトレンド")
    expect(page).to have_no_css("summary", visible: true)
    screenshot!("rename-editing")
    fill_in "名前", with: "途中"
    click_on "やめる"
    expect(page).to have_css("h2", exact_text: "Zenn のトレンド")
    expect(page).to have_no_field("名前")
    expect(menu_open?("Zenn のトレンド")).to be(false)

    menu_of("Zenn のトレンド").click
    click_on "名前を変更"
    fill_in "名前", with: "   "
    click_on "保存"
    expect(page).to have_css(".text-red-600", text: "名前を入力してください")
    expect(feed.reload.title).to eq("Zenn のトレンド")
    screenshot!("rename-error")

    fill_in "名前", with: "Zenn"
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    expect(visible_targets_are_44px).to be(true)
    click_on "保存"

    expect(page).to have_css("h2", exact_text: "Zenn")
    expect(page).to have_no_field("名前")
    expect(find("[data-feed]")).to have_text("1件").and have_css("[data-unread]", exact_text: "未読 1")
    expect(feed.reload.title).to eq("Zenn")
    screenshot!("renamed")
    menu_of("Zenn").click
    dismiss_confirm(/「Zenn」を削除しますか？/) { click_on "削除" }

    find("nav").find_link(href: root_path).click
    expect(page).to have_css("article", text: "記事 A")
    expect(find("article", text: "記事 A")).to have_text("Zenn")
    expect(find("article", text: "記事 A")).to have_no_text("トレンド")
  end

  it "⋯ の開閉: もう一度 ⋯・外を触る・Esc で閉じ、Esc ではフォーカスを ⋯ に戻す。開くのは 1 行だけ" do
    create(:feed, title: "一つ目")
    create(:feed, title: "二つ目")
    sign_in
    click_on "購読"
    expect(page).to have_no_link("名前を変更", visible: true)

    menu_of("一つ目").click
    expect(find("[data-feed]", text: "一つ目")).to have_link("名前を変更", visible: true).and have_button("削除", visible: true)
    native_click(find("h1"))
    expect(menu_open?("一つ目")).to be(false)

    menu_of("一つ目").click
    native_click(menu_of("二つ目"))
    expect(menu_open?("一つ目")).to be(false)
    expect(menu_open?("二つ目")).to be(true)

    find("[data-feed]", text: "二つ目").find_link("名前を変更").send_keys(:escape)
    expect(menu_open?("二つ目")).to be(false)
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')")).to eq("「二つ目」の操作")
  end

  it "入力中は入力欄の上でもラベルの上でも、メニューの項目の上でも、横に指を動かして削除が始まらない" do
    feed = create(:feed, title: "残す購読")
    sign_in
    click_on "購読"
    menu_of("残す購読").click
    swipe(-180, on: find_link("名前を変更"))
    expect(page).to have_text("残す購読")
    click_on "名前を変更"

    swipe(-180, on: find_field("名前"))
    swipe(-180, on: find("label", text: "名前"))

    expect(page).to have_field("名前", with: "残す購読")
    expect(Feed.exists?(feed.id)).to be(true)
  end
end
