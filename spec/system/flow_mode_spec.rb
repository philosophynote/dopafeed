RSpec.describe "FlowMode", type: :system do
  let(:now) { Time.current }

  def create_articles(count, feed: nil)
    (1..count).map { |n| create(:article, title: "記事 #{n}", published_at: now - n.hours, **{ feed: }.compact) }
  end

  def enter_flow_mode
    choose "無限スクロール", allow_label_click: true
    expect(page).to have_css("[data-flow-mode]")
  end

  def scroll_past(title)
    page.execute_script(<<~JS, title)
      const row = [...document.querySelectorAll(".swipe-list > li")].find((li) => li.textContent.includes(arguments[0]))
      window.scrollTo(0, window.scrollY + row.getBoundingClientRect().bottom + 1)
    JS
  end

  def flowed_titles = all("li[data-flowed] article h2", visible: :all).map { |h2| h2.text(:all) }
  def dismissed_titles = Article.where.not(dismissed_at: nil).order(published_at: :desc).pluck(:title)

  it "流すモードで画面の上へ流れ切った行は、止まったときにまとめて削除され、薄く残る。トーストの「元に戻す」で戻った行は流し直さない" do
    create_articles(8)
    sign_in
    switch = find("fieldset.process-mode-switch")
    expect(switch.all("label").map { |label| label.text.lines.first.strip }).to eq(%w[読む 処理 流す])
    expect(switch).to have_field("無限スクロール", visible: :all)
    header = find("header")
    expect(header.evaluate_script("this.scrollWidth <= this.clientWidth")).to be(true)
    expect(header.find_link("設定").evaluate_script("this.getBoundingClientRect().right")).to be <= header.evaluate_script("this.getBoundingClientRect().right")
    expect(page.evaluate_script("document.documentElement.scrollWidth")).to eq(SystemScreen::SCREEN_SIZE[0])
    enter_flow_mode
    screenshot!("header")

    scroll_past("記事 3")
    expect(page).to have_css("#toast [data-controller='toast']", text: "3 件を流しました")
    expect(flowed_titles).to eq([ "記事 1", "記事 2", "記事 3" ])
    expect(dismissed_titles).to eq([ "記事 1", "記事 2", "記事 3" ])
    expect(page).to have_css("[data-unread-badge]", text: "5")
    expect(find("button", text: /片付ける/)).to have_text("残り 5 件を片付ける")
    expect(Reading.count).to eq(0)
    page.execute_script("window.scrollTo(0, 0)")
    screenshot!("flowed")

    find("#toast").click_on("元に戻す")
    expect(page).to have_no_css("li[data-flowed]", visible: :all)
    expect(dismissed_titles).to be_empty
    expect(page).to have_css("[data-unread-badge]", text: "8")

    scroll_past("記事 4")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を流しました")
    expect(dismissed_titles).to eq([ "記事 4" ])
  end

  it "薄い行をタップすると、その 1 本だけが戻り、トーストは残る" do
    create_articles(8)
    sign_in
    enter_flow_mode
    scroll_past("記事 2")
    expect(page).to have_css("#toast [data-controller='toast']", text: "2 件を流しました")

    page.execute_script("window.scrollTo(0, 0)")
    find("li[data-flowed]", text: "記事 1").click_on("タップで戻す")
    expect(page).to have_no_css("li[data-flowed]", text: "記事 1")
    expect(flowed_titles).to eq([ "記事 2" ])
    expect(dismissed_titles).to eq([ "記事 2" ])
    expect(page).to have_css("#toast [data-controller='toast']", text: "2 件を流しました")
    expect(page).to have_css("[data-unread-badge]", text: "7")
  end

  it "読むモードでは流れても消えず、流すモードに入る前に上へ流れていた行も消さない。開き直すと読むモードで、流した行は出ない" do
    create_articles(20)
    sign_in
    scroll_past("記事 2")
    # choose はラジオを画面に入れようとして一番上まで戻すので、スクロールを保ったまま切り替える
    page.execute_script("document.querySelector('input[name=mode][value=flow]').click()")
    expect(page).to have_css("[data-flow-mode]")

    scroll_past("記事 3")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を流しました")
    expect(dismissed_titles).to eq([ "記事 3" ])

    find("nav", text: "保存").click_on("保存")
    expect(page).to have_current_path(saved_path)
    page.go_back
    expect(page).to have_css("article h2", text: "記事 4")
    expect(page).to have_no_css("article h2", text: "記事 3")
    expect(page).to have_no_css("[data-flow-mode]")

    visit root_path
    expect(page).to have_checked_field("読む", visible: :all)
    expect(page).to have_no_css("[data-flow-mode]")
    expect(page).to have_css("article h2", text: "記事 2")
    expect(page).to have_no_css("article h2", text: "記事 3")
  end

  it "払った行のトーストが出ている間に流しても、払った行のトーストが残って元に戻せる。流した行は薄い行のタップで戻せる" do
    create_articles(8)
    sign_in
    enter_flow_mode
    delete_row("記事 1")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました")

    scroll_past("記事 3")
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until dismissed_titles.size == 3 }
    expect(flowed_titles).to eq([ "記事 2", "記事 3" ])
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました")

    find("#toast").click_on("元に戻す")
    expect(page).to have_css("article h2", text: "記事 1")
    expect(dismissed_titles).to eq([ "記事 2", "記事 3" ])
  end

  it "流した分を送れなかったら、行は薄さが取れて未読のまま残る" do
    create_articles(8)
    sign_in
    enter_flow_mode
    page.execute_script(<<~JS)
      const form = document.querySelector("[data-flow-target=form]")
      document.addEventListener("turbo:submit-end", (event) => { if (event.target === form) window.flowEnded = true })
    JS

    page.driver.browser.network_conditions = { offline: true, latency: 0, throughput: 0 }
    begin
      scroll_past("記事 2")
      Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until page.evaluate_script("window.flowEnded") }
      expect(page).to have_no_css("li[data-flowed]", visible: :all)
    ensure
      # 同じブラウザを次の例も使うので、圏外のまま残さない
      page.driver.browser.network_conditions = { offline: false, latency: 0, throughput: -1 }
    end
    expect(dismissed_titles).to be_empty
    expect(page).to have_no_css("#toast [data-controller='toast']")
  end

  it "広げたまま別の画面へ移って戻っても、広げた行は流さない" do
    create_articles(8)
    sign_in
    expand("記事 1")
    find("nav", text: "保存").click_on("保存")
    expect(page).to have_current_path(saved_path)
    page.go_back
    expect(find("li[id^='article_']", text: "記事 1")).to have_link("記事に遷移")
    enter_flow_mode

    scroll_past("記事 2")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を流しました")
    expect(dismissed_titles).to eq([ "記事 2" ])
  end

  it "処理モードで払ってから「流す」に切り替えると、処理のリザルトが出る" do
    create_articles(3)
    sign_in
    enter_process_mode
    delete_row("記事 1")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました")

    enter_flow_mode
    expect(find("dialog[open]", text: "リザルト")).to have_text("1 件 処理した", normalize_ws: true)
  end

  it "広げた行は流れても消さない" do
    create_articles(8)
    sign_in
    enter_flow_mode
    expand("記事 1")

    scroll_past("記事 2")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を流しました")
    expect(dismissed_titles).to eq([ "記事 2" ])
  end

  it "最後の行まで流し切ると「全部流した」と出る" do
    create_articles(3)
    sign_in
    enter_flow_mode

    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
    expect(page).to have_css("#toast [data-controller='toast']", text: "3 件を流しました")
    expect(page).to have_text("全部流した。")
    expect(page.evaluate_script("document.querySelector('.flow-done').getBoundingClientRect().top")).to be_between(0, SystemScreen::SCREEN_SIZE[1])
    expect(dismissed_titles).to eq([ "記事 1", "記事 2", "記事 3" ])
    screenshot!("all_flowed")
  end

  def scroll_to_end = page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")

  def wait_for_scroll_top
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until page.evaluate_script("window.scrollY").zero? }
  end

  def within_screen?(selector)
    page.evaluate_script(<<~JS, selector)
      ((rect) => rect.top >= 0 && rect.bottom <= window.innerHeight)(document.querySelector(arguments[0]).getBoundingClientRect())
    JS
  end

  def zenn_and_qiita
    zenn = create(:feed, title: "Zenn")
    qiita = create(:feed, title: "Qiita")
    (1..3).each { |n| create(:article, feed: zenn, title: "Zenn #{n}", published_at: now - n.hours) }
    (1..5).each { |n| create(:article, feed: qiita, title: "Qiita #{n}", published_at: now - n.hours) }
    [ zenn, qiita ]
  end

  it "絞ったフィードを流し切ると「先頭に戻る」が出て、押すと先頭に戻り、選んでいるチップにフォーカスが移る。流すモードのままで、新たに流れない" do
    zenn, = zenn_and_qiita
    sign_in
    visit root_path(feed: zenn.id)
    enter_flow_mode

    scroll_to_end
    expect(page).to have_css("#toast [data-controller='toast']", text: "3 件を流しました")
    expect(page).to have_text("全部流した。")
    expect(within_screen?(".flow-end [data-action~='flow#toTop']")).to be(true)
    expect(page.evaluate_script("document.documentElement.scrollWidth")).to eq(SystemScreen::SCREEN_SIZE[0])
    screenshot!("end")
    count_flow_submits

    click_on "先頭に戻る"
    wait_for_scroll_top
    expect(within_screen?("nav.feed-filter")).to be(true)
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-current')")).to eq("page")
    expect(page.evaluate_script("document.activeElement.textContent")).to include("Zenn")
    expect(page).to have_css("[data-flow-mode]")
    expect(flow_submits_after_settling).to eq(0)
    expect(dismissed_titles).to eq([ "Zenn 1", "Zenn 2", "Zenn 3" ])
  end

  it "流さずに残した行があっても、一番下まで来れば「先頭に戻る」が出る（「全部流した。」は出ない）" do
    create_articles(3)
    sign_in
    enter_flow_mode
    expand("記事 1")

    scroll_to_end
    expect(page).to have_css("#toast [data-controller='toast']", text: "2 件を流しました")
    expect(page).to have_button("先頭に戻る")
    expect(page).to have_no_text("全部流した。")
  end

  it "読むモードでは一番下まで来ても「先頭に戻る」は出ない" do
    create_articles(3)
    sign_in

    scroll_to_end
    expect(page).to have_no_button("先頭に戻る")
  end

  it "「次は Qiita 5 件を流す」を押すと、スクロールが止まる前でも今のフィードの流した分を送り切ってから、流すモードのまま Qiita を開く。再読込すると読むで始まる" do
    zenn, qiita = zenn_and_qiita
    sign_in
    visit root_path(feed: zenn.id)
    enter_flow_mode

    # スクロールが止まる前に押した場合。流れた行はまだ送られていない
    page.execute_script(<<~JS)
      window.holdScrollend = (event) => event.stopImmediatePropagation()
      window.addEventListener("scrollend", window.holdScrollend, true)
    JS
    scroll_to_end
    expect(page).to have_css("li[data-flowed]", count: 3, visible: :all)
    expect(dismissed_titles).to be_empty
    find(".flow-end").click_on("次は Qiita 5 件を流す")
    expect(page).to have_current_path(root_path(feed: qiita.id))
    expect(page).to have_css("article h2", text: "Qiita 1")
    expect(page).to have_checked_field("無限スクロール", visible: :all)
    expect(page).to have_css("[data-flow-mode]")
    expect(dismissed_titles).to eq([ "Zenn 1", "Zenn 2", "Zenn 3" ])
    expect(page).to have_no_link(text: /次は/)

    page.execute_script("window.removeEventListener('scrollend', window.holdScrollend, true)")
    scroll_past("Qiita 2")
    expect(page).to have_css("#toast [data-controller='toast']", text: "2 件を流しました")

    visit current_url
    expect(page).to have_checked_field("読む", visible: :all)
    expect(page).to have_no_css("[data-flow-mode]")
  end

  def flow_submits_after_settling
    page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      setTimeout(() => requestAnimationFrame(() => requestAnimationFrame(() => done(window.flowSubmits || 0))), 200)
    JS
  end

  def count_flow_submits
    page.execute_script(<<~JS)
      const form = document.querySelector("[data-flow-target=form]")
      document.addEventListener("turbo:submit-start", (event) => { if (event.target === form) window.flowSubmits = (window.flowSubmits || 0) + 1 })
    JS
  end

  it "流すモードで片付けて元に戻した行は、「読む」に切り替えても消えない" do
    create_articles(3)
    sign_in
    enter_flow_mode
    count_flow_submits

    find("button", text: /片付ける/).click
    expect(page).to have_css("#toast [data-controller='toast']", text: "3 件を片付けました")
    find("#toast").click_on("元に戻す")
    expect(page).to have_css("article h2", text: "記事 3")
    choose "読む", allow_label_click: true

    expect(flow_submits_after_settling).to eq(0)
    expect(dismissed_titles).to be_empty
  end

  it "ほかで先に消えていた記事は、流しても薄い行にならない（戻すで、ほかの削除を外さない）" do
    create_articles(8)
    sign_in
    enter_flow_mode
    Article.find_by!(title: "記事 2").dismiss!

    scroll_past("記事 3")
    expect(page).to have_css("#toast [data-controller='toast']", text: "2 件を流しました")
    expect(flowed_titles).to eq([ "記事 1", "記事 3" ])
    expect(page).to have_no_css("li[data-flowed]", text: "記事 2", visible: :all)
  end

  it "1 本だけタップで戻して広げた後にトーストで残りを戻しても、広げた欄は畳まれない" do
    create(:article, title: "記事 1", summary: "・要約", published_at: now - 1.hour)
    (2..8).each { |n| create(:article, title: "記事 #{n}", published_at: now - n.hours) }
    sign_in
    enter_flow_mode
    scroll_past("記事 2")
    expect(page).to have_css("#toast [data-controller='toast']", text: "2 件を流しました")
    page.execute_script("window.scrollTo(0, 0)")
    find("li[data-flowed]", text: "記事 1").click_on("タップで戻す")
    expect(page).to have_no_css("li[data-flowed]", text: "記事 1")
    expand("記事 1")

    find("#toast").click_on("元に戻す")
    expect(page).to have_no_css("li[data-flowed]", visible: :all)
    expect(find("li[id^='article_']", text: "記事 1")).to have_link("記事に遷移")
    expect(dismissed_titles).to be_empty
  end

  it "scrollend の無いブラウザでも、流れた分は送られる" do
    script = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      delete window.onscrollend
      delete Window.prototype.onscrollend
      window.addEventListener("scrollend", (event) => event.stopImmediatePropagation(), true)
    JS
    begin
      create_articles(8)
      sign_in
      expect(page.evaluate_script("'onscrollend' in window")).to be(false)
      enter_flow_mode

      scroll_past("記事 3")
      expect(page).to have_css("#toast [data-controller='toast']", text: /件を流しました/)
      Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until dismissed_titles.size == 3 }
      expect(dismissed_titles).to eq([ "記事 1", "記事 2", "記事 3" ])
    ensure
      # 同じブラウザを次の例も使うので、scrollend の無いまま残さない
      page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"])
    end
  end

  it "薄い行の「戻す」は、読み上げで記事の見出しが分かる" do
    create_articles(8)
    sign_in
    enter_flow_mode
    scroll_past("記事 2")
    expect(page).to have_css("#toast [data-controller='toast']", text: "2 件を流しました")

    names = all(".flow-restore", visible: :all).map { |button| button.text(:all).squish }
    expect(names).to eq([ "「記事 1」を流した ・ タップで戻す", "「記事 2」を流した ・ タップで戻す" ])
  end

  it "Tab で行をたどって画面がスクロールしても、流さない" do
    create_articles(20, feed: create(:feed))
    sign_in
    enter_flow_mode
    count_flow_submits

    find("body").send_keys(*Array.new(20, :tab))
    expect(page.evaluate_script("window.scrollY")).to be > 0
    expect(flow_submits_after_settling).to eq(0)
    expect(page).to have_no_css("li[data-flowed]", visible: :all)
    expect(dismissed_titles).to be_empty
  end
end
