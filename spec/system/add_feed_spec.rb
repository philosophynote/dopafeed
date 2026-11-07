RSpec.describe "AddFeed", type: :system do
  it "Main から開き、エラー後も入力を保ち、追加して閉じると元に戻る" do
    url = "https://fixtures.example.com/feed.xml"
    stub_request(:get, url).to_return(status: 503)
    sign_in
    click_on "フィードを追加"
    within("dialog[open]") do
      fill_in "フィードまたはサイトの URL", with: url
      page.execute_script("window.__feedFetch = window.fetch; window.fetch = (...args) => new Promise(resolve => { window.__releaseFeed = () => resolve(window.__feedFetch(...args)) })")
      click_on "追加", exact: true
      expect(page).to have_css("dialog button:disabled", count: 6)
      page.execute_script("window.fetch = window.__feedFetch; window.__releaseFeed()")
      expect(page).to have_text("サーバーエラー (HTTP 503)")
      expect(page).to have_field("フィードまたはサイトの URL", with: url)
      stub_request(:get, url).to_return(body: file_fixture("feeds/rss2.xml").read)
      click_on "追加", exact: true
      expect(page).to have_text("Fixture RSS")
      expect(page).to have_text("記事を取得しています")
      click_on "閉じる"
    end
    expect(page).to have_current_path(root_path)
    expect(page).to have_no_css("dialog[open]")
  end

  it "購読からおすすめを追加し、登録済み表示と Escape・閉じる操作を通す" do
    stub_request(:get, "https://zenn.dev/feed").to_return(body: file_fixture("feeds/atom.xml").read)
    sign_in
    click_on "購読"
    expect(page).to have_current_path(feeds_path)
    expect(page).to have_css("h1", text: "購読 (0)")
    click_on "フィードを追加"
    expect(page).to have_css("dialog[open]")
    expect(viewport_width).to eq(390)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    expect(page.evaluate_script("Array.from(document.querySelector('dialog').querySelectorAll('a, button, input:not([type=hidden])')).every(e => { const r = e.getBoundingClientRect(); return r.width >= 44 && r.height >= 44 })")).to be(true)
    screenshot!("sheet")
    click_on "Zenn トレンド"
    expect(page).to have_text("Fixture Atom")
    screenshot!("success")
    find("dialog").send_keys(:escape)
    expect(page).to have_current_path(feeds_path)
    expect(page).to have_css("[data-feed]", text: "Fixture Atom")
    click_on "フィードを追加"
    click_on "Zenn トレンド"
    expect(page).to have_text("登録済み")
    find("dialog").send_keys(:escape)
    expect(page).to have_no_css("dialog[open]")
  end
  it "サイトの入力を保って未検出・時間切れを表示し、検出した購読を一覧に反映する" do
    site = "https://fixtures.example.com/"
    stub_request(:get, site).to_return(body: "<html></html>", headers: { "Content-Type" => "text/html" })
    %w[feed rss atom.xml index.xml].each { |path| stub_request(:get, "#{site}#{path}").to_return(status: 404) }
    sign_in
    visit feeds_path
    click_on "フィードを追加"
    fill_in "フィードまたはサイトの URL", with: site
    click_on "追加", exact: true
    expect(page).to have_text("フィードが見つかりません")
    expect(page).to have_field("フィードまたはサイトの URL", with: site)
    screenshot!("not_found")
    allow(HttpGet).to receive(:call).and_raise(FeedDiscovery::Expired)
    click_on "追加", exact: true
    expect(page).to have_text("確認がタイムアウト")
    expect(page).to have_field("フィードまたはサイトの URL", with: site)
    allow(HttpGet).to receive(:call).and_call_original
    stub_request(:get, "#{site}feed").to_return(body: file_fixture("feeds/rss2.xml").read)
    click_on "追加", exact: true
    expect(page).to have_text("Fixture RSS")
    screenshot!("discovered")
    click_on "閉じる"
    expect(page).to have_css("[data-feed]", text: "Fixture RSS")
  end
end
