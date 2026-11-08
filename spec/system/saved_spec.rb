# Saved を 390×844 で開く。タブバーからの動線、見た目の崩れ（横スクロール・タップ領域）、未読と読んだ行の開き方
RSpec.describe "Saved", type: :system do
  it "タブバーの「保存」から開き、保存した新しい順に並ぶ。横スクロールが無く、タップ領域は 44px 以上" do
    feed = create(:feed, title: "Ruby Weekly")
    create(:article, feed: feed, title: "先に保存した、390 幅で折り返されるくらいに長い見出しの記事",
                     image_url: "/icon.png", bookmarked_at: 2.days.ago, published_at: 3.days.ago)
    create(:article, :read, feed: feed, title: "後に保存して読み終えた記事", bookmarked_at: 1.day.ago, published_at: 2.days.ago)
    create(:article, title: "Main に残る記事")
    sign_in

    expect(page).to have_css("article", count: 1)
    find("nav").click_link("保存")

    expect(page).to have_css("h1", text: "保存 (2)")
    expect(page.all("article h2").map(&:text)).to eq([ "後に保存して読み終えた記事", "先に保存した、390 幅で折り返されるくらいに長い見出しの記事" ])
    expect(find("article", text: "読み終えた")).to have_text("読んだ")
    expect(find("nav").find_link("保存")["aria-current"]).to eq("page")
    expect(viewport_width).to eq(390)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    small = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("a, button")).filter(el => el.getClientRects().length > 0).map(el => {
        const r = el.getBoundingClientRect();
        return [el.textContent.trim() || el.getAttribute("aria-label"), Math.round(r.width), Math.round(r.height)];
      }).filter(([, w, h]) => w < 44 || h < 44)
    JS
    expect(small).to be_empty, "44px 未満のタップ領域: #{small.inspect}"
    screenshot!("list")
  end

  it "未読の行を押すとルーレットが回り、読んだ行を押すと抽選せずに Reader が開く" do
    unread = create(:article, :bookmarked, title: "まだ読んでいない保存記事")
    read = create(:article, :bookmarked, :read, title: "読み終えた保存記事")
    sign_in
    visit saved_path

    find("article", text: "読み終えた保存記事").find_link("を開く", visible: :all).click
    expect(page).to have_current_path(read_article_path(read))
    expect(page).to have_css("h1", text: "読み終えた保存記事")

    visit saved_path
    find("article", text: "まだ読んでいない保存記事").find_button("を読む", visible: :all).click
    expect(page).to have_css("[role='dialog'][aria-label='ルーレット']")
    expect(unread.reload.reading).to be_present
  end

  it "保存が 0 本なら空状態" do
    sign_in
    visit saved_path

    expect(page).to have_css("h1", text: "保存 (0)")
    expect(page).to have_text("まだ保存した記事はありません。")
    screenshot!("empty")
  end
end
