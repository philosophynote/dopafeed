# Install（docs/screens/install.md）の standalone の分岐と、アイコンのバッジ（Badging API）。
# iOS の「ホーム画面から開いた」は Selenium では作れないので、navigator.standalone（か display-mode）を偽って同じ分岐を踏ませる。
# setAppBadge / clearAppBadge は呼ばれた引数を window.__badges に積む代物に置き換え、「呼んだ」ことまでを検証する
# （iOS で本当にバッジが出るかは通知の許可に掛かるので、実機でしか分からない）
RSpec.describe "Install", type: :system do
  # 新しい文書ごとに先回りで入れるスクリプト（ページの JS より先に走るので、Stimulus の connect が見る値を変えられる）。
  # ブラウザは例をまたいで使い回されるので、入れたものは after で外す
  def emulate_standalone!(via: :navigator)
    detection = if via == :navigator
      'Object.defineProperty(navigator, "standalone", { value: true, configurable: true });'
    else
      'window.matchMedia = (query) => ({ matches: query === "(display-mode: standalone)", media: query });'
    end
    @standalone_script = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      #{detection}
      window.__badges = [];
      navigator.setAppBadge = (count) => { window.__badges.push(count); return Promise.resolve(); };
      navigator.clearAppBadge = () => { window.__badges.push("clear"); return Promise.resolve(); };
    JS
  end

  after do
    next unless @standalone_script

    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: @standalone_script["identifier"])
  rescue Selenium::WebDriver::Error::WebDriverError => e
    # ブラウザが固まった例の後に、外す命令でもう一度 read timeout を待たない（次の例は新しい Chrome で始まる）
    warn "standalone stub not removed: #{e.class}"
  end

  # Stimulus が connect するまで待ってから最後の呼び出しを見る
  def expect_last_badge(value)
    page.document.synchronize do
      last = page.evaluate_script("window.__badges[window.__badges.length - 1]")
      raise Capybara::ElementNotFound, "last badge call was #{last.inspect}" unless last == value
    end
  end

  it "Safari のタブで開くと手順 3 段と注記が出て「通知を許可する」は無効" do
    sign_in
    visit install_path

    expect(page).to have_css("ol[aria-label='手順'] li", count: 3)
    expect(page).to have_button("通知を許可する", disabled: true)
    expect(page).to have_text("Safari のタブのままでは通知もバッジも使えません")
    expect(page).to have_no_text("ホーム画面から開いています")
  end

  it "ホーム画面から開く（navigator.standalone）と注記が変わり、アイコンに未読数のバッジが付く" do
    create_list(:article, 3)
    emulate_standalone!

    sign_in
    expect(page).to have_css("[data-unread-badge]", text: "3")
    expect_last_badge(3)

    visit install_path
    expect(page).to have_text("ホーム画面から開いています")
    expect(page).to have_no_text("Safari のタブのままでは通知もバッジも使えません")
    expect_last_badge(3)
    screenshot!("standalone")
  end

  it "display-mode: standalone でも同じ分岐に入る" do
    emulate_standalone!(via: :display_mode)

    sign_in
    visit install_path

    expect(page).to have_text("ホーム画面から開いています")
  end

  it "未読が 0 ならバッジを消す" do
    emulate_standalone!

    sign_in
    expect(page).to have_text("全部読んだ")
    expect_last_badge("clear")
  end

  it "「興味なし」で未読が減ると、アイコンのバッジも書き直す" do
    create_list(:article, 2)
    emulate_standalone!

    sign_in
    expect_last_badge(2)
    click_on "興味なし", match: :first

    expect(page).to have_text("元に戻す")
    expect_last_badge(1)
  end
end
