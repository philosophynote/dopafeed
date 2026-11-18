RSpec.describe "Delete mode", type: :system do
  let(:now) { Time.current }
  let(:ratio) { Dopamine.settings.dig(:swipe, :dismiss_threshold_ratio) }

  it "「削除」に切り替えると行ごとに削除ボタンが出て、押すと行が消えてトーストが出て未読数が減る。「読む」に戻すとボタンが消える" do
    create(:article, title: "上の記事", published_at: now - 1.hour)
    create(:article, title: "消す記事", published_at: now - 2.hours)
    create(:article, title: "下の記事", published_at: now - 3.hours)
    sign_in

    mode = find("fieldset", text: "読む")
    expect(mode).to have_checked_field("読む", visible: :all)
    mode.all("label").each { |label| expect(label.evaluate_script("this.getBoundingClientRect().height")).to be >= 44 }
    expect(page).to have_no_button("削除")

    enter_delete_mode
    expect(page).to have_button("削除", count: 3)
    expect(page).to have_css("button[data-swipe-target='read'][inert]", visible: :all, count: 3)
    button = find("li", text: "消す記事").find_button("削除")
    rect = button.evaluate_script("this.getBoundingClientRect().toJSON()")
    expect([ rect["width"], rect["height"] ].min).to be >= 44
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    screenshot!("on")

    delete_row("消す記事")

    toast = find("#toast [data-controller='toast']", text: "1 件を削除しました")
    expect(page).to have_no_css("article", text: "消す記事")
    expect(page).to have_css("[data-unread-badge]", text: "2")
    expect(Article.find_by!(title: "消す記事")).to be_dismissed
    expect(Reading.count).to eq(0)
    # 登場中は translateY でタブバーに重なるため、アニメーション後の配置を測る。
    page.evaluate_async_script(<<~JS, toast.native)
      const [toast, done] = arguments
      Promise.all(toast.getAnimations().map((animation) => animation.finished)).then(() => done(true))
    JS
    toast_rect = toast.evaluate_script("this.getBoundingClientRect().toJSON()")
    nav_top = find("nav[aria-label='タブバー']").evaluate_script("this.getBoundingClientRect().top")
    expect(toast_rect["bottom"]).to be <= nav_top
    expect(toast_rect["left"]).to be >= 0
    expect(toast_rect["right"]).to be <= page.evaluate_script("document.documentElement.clientWidth")
    expect(toast.find_button("元に戻す").evaluate_script("this.getBoundingClientRect().height")).to be >= 44
    screenshot!("deleted")
    # yml に toast.visible_seconds が無ければ、トーストは時間では消えない
    sleep 1.5
    expect(page).to have_css("#toast [data-controller='toast']", wait: 0)

    find("#toast").click_on("元に戻す")
    expect(page).to have_css("article", count: 3)
    expect(all("article h2").map(&:text)).to eq(%w[上の記事 消す記事 下の記事])
    expect(page).to have_button("削除", count: 3)
    expect(page).to have_css("button[data-swipe-target='read'][inert]", visible: :all, count: 3)
    expect(Article.find_by!(title: "消す記事")).not_to be_dismissed

    choose "読む", allow_label_click: true
    expect(page).to have_no_button("削除")
    expect(page).to have_no_css("button[data-swipe-target='read'][inert]", visible: :all)
    expect(page).to have_button("「消す記事」を読む")
  end

  it "続けて押すと押した分だけ消える（送信は 1 本ずつ）。指で押しても送られる" do
    titles = %w[一本目 二本目 三本目 四本目]
    titles.each_with_index { |title, i| create(:article, title: title, published_at: now - (i + 1).hours) }
    sign_in
    enter_delete_mode

    delete_row("一本目", native: true)
    delete_row("二本目")
    delete_row("三本目")

    expect(page).to have_css("article", count: 1)
    third = Article.find_by!(title: "三本目")
    expect(page).to have_css("#toast [data-controller='toast']", count: 1)
    expect(page).to have_css("#toast form[action='#{article_dismissal_path(third)}']")
    expect(page).to have_css("[data-unread-badge]", text: "1")
    expect(Article.where.not(dismissed_at: nil).pluck(:title)).to match_array(%w[一本目 二本目 三本目])
  end

  it "削除モードでは行を押しても広がらず、左右に引いても動かない。切り替えると広げていた欄は畳む" do
    create(:article, title: "広げた記事", summary: "・要約", published_at: now - 1.hour)
    create(:article, title: "触る記事", published_at: now - 2.hours)
    sign_in
    find("article", text: "広げた記事").find_button("読む").execute_script("this.click()")
    expect(page).to have_link("記事に遷移")

    enter_delete_mode
    expect(page).to have_no_link("記事に遷移")

    page.execute_script("window.__starts = 0; document.addEventListener('turbo:submit-start', () => window.__starts++)")
    native_click(find("article", text: "触る記事"))
    sleep 0.5
    expect(page.evaluate_script("window.__starts")).to eq(0)
    expect(page).to have_no_link("記事に遷移")
    width = card_width("触る記事")
    drag_card("触る記事", from: [ width / 2, 40 ], to: [ width / 2 + width * ratio * 1.3, 40 ], release: false)
    expect(card_shift("触る記事")).to eq(0)
    drag_card("触る記事", from: [ width / 2, 40 ], to: [ width / 2 - width * ratio * 1.3, 40 ], down: false)

    expect(page).to have_css("article", count: 2)
    expect(Article.find_by!(title: "触る記事").reading).to be_nil
    expect(Article.find_by!(title: "触る記事")).not_to be_bookmarked
  end

  it "同じ削除ボタンを続けて押しても送信は 1 本" do
    create(:article, title: "二度押す記事", published_at: now - 1.hour)
    create(:article, title: "残る記事", published_at: now - 2.hours)
    sign_in
    enter_delete_mode
    # 応答の描画を遅らせ、押した行がまだ画面にある間にもう一度押す
    page.execute_script(<<~JS)
      window.__starts = 0
      document.addEventListener("turbo:submit-start", () => window.__starts++)
      document.addEventListener("turbo:before-stream-render", (event) => {
        const render = event.detail.render
        event.detail.render = (stream) => new Promise((resolve) => setTimeout(() => resolve(render(stream)), 500))
      })
    JS

    button = find("li", text: "二度押す記事").find_button("削除")
    native_click(button)
    native_click(button)

    expect(page).to have_css("#toast [data-controller='toast'][data-toast-swipe-value='1']")
    expect(page).to have_css("article", count: 1)
    expect(page.evaluate_script("window.__starts")).to eq(1)
  end

  it "「読む」の応答を待つ間に「削除」へ切り替えたら、届いた応答で行は開かない" do
    create(:article, title: "待つ記事", summary: "・要約", published_at: now - 1.hour)
    sign_in
    # POST の応答を、切り替えた後まで手で止めておく
    page.execute_script(<<~JS)
      window.__fetch = window.fetch
      window.fetch = (url, options) => (options?.method || "GET").toUpperCase() === "POST"
        ? new Promise((resolve) => { window.__release = () => resolve(window.__fetch(url, options)) })
        : window.__fetch(url, options)
    JS

    read_button = find("article", text: "待つ記事").find_button("読む")
    read_button.execute_script("this.click()")
    page.document.synchronize { raise Capybara::ElementNotFound, "「読む」が送られない" unless page.evaluate_script("typeof window.__release") == "function" }
    enter_delete_mode
    page.execute_script("window.__release()")

    expect(page).to have_css("[data-swipe-target='detail'] *", visible: :all, wait: 5)
    expect(page).to have_no_link("記事に遷移")
    expect(read_button["aria-expanded"]).to eq("false")
  end

  it "画面を移って戻る・再読込すると「読む」で始まる" do
    create(:article, title: "記事", published_at: now - 1.hour)
    sign_in
    enter_delete_mode

    click_on "設定"
    expect(page).to have_css("h1", text: "設定")
    page.go_back
    expect(page).to have_checked_field("読む", visible: :all)
    expect(page).to have_no_button("削除")

    enter_delete_mode
    page.refresh
    expect(page).to have_checked_field("読む", visible: :all)
    expect(page).to have_no_button("削除")
  end

  it "削除モードで最後の 1 本を消しても切り替えは残り、「読む」に戻すと空状態とともに切り替えが消える。元に戻せばまた出る" do
    create(:article, title: "最後の記事", published_at: now - 1.hour)
    sign_in
    enter_delete_mode

    delete_row("最後の記事")
    expect(page).to have_text("全部読んだ。")
    expect(page).to have_css("fieldset.delete-mode-switch")

    choose "読む", allow_label_click: true
    find("dialog[open]").click_on "閉じる"
    expect(page).to have_no_css("fieldset.delete-mode-switch")
    expect(page).to have_link("設定")

    find("#toast").click_on("元に戻す")
    expect(page).to have_css("article", text: "最後の記事")
    expect(page).to have_css("fieldset.delete-mode-switch")
  end

  it "未読が 0 本ならモードの切り替えは出ない" do
    sign_in
    expect(page).to have_text("全部読んだ。")
    expect(page).to have_no_field("削除", visible: :all)
  end

  context "コンボとリザルト" do
    def sfx_log
      page.evaluate_script('JSON.parse(sessionStorage.getItem("sfx-log") || "[]")')
    end

    def melody_notes
      levels = page.evaluate_script('JSON.parse(sessionStorage.getItem("sfx-log-levels") || "[]")')
      sfx_log.zip(levels).filter_map { |cue, level| level if cue == "melody" }
    end

    # 時間は performance.now で測る。秒を決めて検査するため、手で進める時計に差し替える
    def freeze_clock
      page.execute_script("window.__now = 0; performance.now = () => window.__now")
    end

    def advance_clock(ms)
      page.execute_script("window.__now += #{ms}")
    end

    # 削除の POST を、release_posts を呼ぶまで手で止めておく
    def hold_posts
      page.execute_script(<<~JS)
        window.__fetch = window.fetch
        window.__held = []
        window.fetch = (url, options) => (options?.method || "GET").toUpperCase() === "POST" && !window.__open
          ? new Promise((resolve) => window.__held.push(() => resolve(window.__fetch(url, options))))
          : window.__fetch(url, options)
      JS
    end

    def release_posts
      page.execute_script("window.__open = true; window.__held.splice(0).forEach((send) => send())")
    end

    def combo
      find("[data-delete-mode-target='combo']")
    end

    before do
      %w[一本目 二本目 三本目 四本目].each_with_index { |title, i| create(:article, title: title, published_at: now - (i + 1).hours) }
    end

    it "削除するたびにコンボが 1 増えてメロディの次の音が鳴り、元に戻すと 1 減って次は同じ音を鳴らし直す。コンボはステータスの行に重ね、行の高さも読了の「n 連続」も変えない" do
      2.times { |i| create(:reading, :completed, opened_at: now - (i + 1).minutes - 10.minutes) }
      sign_in
      status_top = find("section[aria-label='記事']").evaluate_script("this.getBoundingClientRect().top")
      expect(page).to have_css("[data-combo]", text: "2 連続", visible: :all)
      enter_delete_mode
      expect(combo).to have_text("0 COMBO", normalize_ws: true)
      expect(combo["aria-atomic"]).to eq("true")
      expect(find("section[aria-label='記事']").evaluate_script("this.getBoundingClientRect().top")).to eq(status_top)
      expect(page).to have_css("[inert] #status-card", visible: :all)

      delete_row("一本目")
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
      delete_row("二本目")
      expect(combo).to have_text("2 COMBO", normalize_ws: true)
      expect(page).to have_css("article", count: 2)
      expect(melody_notes).to eq([ 1, 2 ])
      expect(sfx_log).not_to include("combo")
      screenshot!("combo")

      find("#toast").click_on("元に戻す")
      expect(page).to have_css("article", text: "二本目")
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
      expect(Article.where.not(dismissed_at: nil).count).to eq(1)
      expect(page).to have_css("[data-combo]", text: "2 連続", visible: :all)
      delete_row("二本目")
      expect(combo).to have_text("2 COMBO", normalize_ws: true)
      delete_row("三本目")
      expect(combo).to have_text("3 COMBO", normalize_ws: true)
      expect(melody_notes).to eq([ 1, 2, 2, 3 ])

      choose "読む", allow_label_click: true
      find("dialog[open]").click_on "閉じる"
      expect(page).to have_no_css("[inert] #status-card", visible: :all)
    end

    it "「読む」に戻すと、かかった時間と件数と 1 件あたりの秒数のリザルトが重なって出て、ファンファーレが鳴る。閉じると次の回は 0 から" do
      sign_in
      freeze_clock
      enter_delete_mode
      delete_row("一本目")
      delete_row("二本目")
      delete_row("三本目")
      expect(page).to have_css("article", count: 1)
      advance_clock(83_000)

      choose "読む", allow_label_click: true

      result = find("dialog[open]", text: "リザルト")
      expect(result).to have_text("3 件", normalize_ws: true)
      expect(result).to have_text("1 分 23 秒", normalize_ws: true)
      expect(result).to have_text("27.7 秒", normalize_ws: true)
      expect(sfx_log.last).to eq("fanfare")
      expect(result.find_button("閉じる").evaluate_script("this.getBoundingClientRect().height")).to be >= 44
      screenshot!("result")

      result.click_on "閉じる"
      expect(page).to have_no_css("dialog[open]")
      enter_delete_mode
      expect(combo).to have_text("0 COMBO", normalize_ws: true)
    end

    it "続けて押してすぐ「読む」に戻しても、押した分がリザルトに入る。後から届いた応答は次の回のコンボに数えない" do
      sign_in
      enter_delete_mode
      hold_posts
      delete_row("一本目")
      delete_row("二本目")
      delete_row("三本目")
      choose "読む", allow_label_click: true

      expect(find("dialog[open]")).to have_text("3 件", normalize_ws: true)
      find("dialog[open]").click_on "閉じる"
      enter_delete_mode
      release_posts

      expect(page).to have_css("article", count: 1)
      expect(Article.where.not(dismissed_at: nil).count).to eq(3)
      find("#toast").click_on("元に戻す")
      expect(page).to have_css("article", count: 2)
      expect(combo).to have_text("0 COMBO", normalize_ws: true)
    end

    it "送れなかった削除はコンボから引く" do
      sign_in
      enter_delete_mode
      # 圏外で送れなかったときと同じく、最初の削除の POST だけを失敗させる
      page.execute_script(<<~JS)
        const original = window.fetch
        window.fetch = (url, options) => (options?.method || "GET").toUpperCase() === "POST" && !window.__failed
          ? (window.__failed = true, Promise.reject(new TypeError("Failed to fetch")))
          : original(url, options)
        window.__ended = 0
        document.addEventListener("turbo:submit-end", () => window.__ended++)
      JS

      delete_row("一本目")
      page.document.synchronize { raise Capybara::ExpectationNotMet, "送信が終わらない" unless page.evaluate_script("window.__ended") == 1 }
      expect(page).to have_css("article", count: 4)
      expect(combo).to have_text("0 COMBO", normalize_ws: true)

      delete_row("一本目")
      expect(page).to have_css("article", count: 3)
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
    end

    it "待ちの上限を越えて失敗に見えた削除も、後から成功が届けばコンボに数え直す" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(swipe: { submit_timeout_seconds: 1 }))
      sign_in
      enter_delete_mode
      page.execute_script(<<~JS)
        const original = window.fetch
        window.fetch = (url, options) => (options?.method || "GET").toUpperCase() === "POST"
          ? new Promise((resolve) => setTimeout(() => resolve(original(url, options)), 2500))
          : original(url, options)
      JS

      delete_row("一本目")
      expect(combo).to have_text("0 COMBO", normalize_ws: true, wait: 2)
      expect(page).to have_css("article", count: 3, wait: 5)
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
    end

    it "1 件も消さずに「読む」に戻すとリザルトは出ない。1 分に満たなければ秒だけ出す" do
      sign_in
      freeze_clock
      enter_delete_mode
      choose "読む", allow_label_click: true
      sleep 0.3
      expect(page).to have_no_css("dialog[open]")

      enter_delete_mode
      delete_row("一本目")
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
      advance_clock(9_500)
      choose "読む", allow_label_click: true
      result = find("dialog[open]")
      expect(result).to have_text("1 件", normalize_ws: true)
      expect(result).to have_text("9 秒", normalize_ws: true)
      expect(result).to have_no_text("分")
    end

    it "リザルトは枠の外を押すと閉じ、枠の中の余白を押しても閉じない。開いたまま画面を移って戻ると閉じている" do
      sign_in
      enter_delete_mode
      delete_row("一本目")
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
      choose "読む", allow_label_click: true
      result = find("dialog[open]")

      rect = result.evaluate_script("this.getBoundingClientRect().toJSON()")
      page.driver.browser.action.move_to_location(rect["left"] + rect["width"] / 2, rect["top"] + 4).click.perform
      expect(page).to have_css("dialog[open]")
      page.driver.browser.action.move_to_location(rect["left"] / 2, rect["top"] / 2).click.perform
      expect(page).to have_no_css("dialog[open]")

      enter_delete_mode
      delete_row("二本目")
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
      choose "読む", allow_label_click: true
      expect(page).to have_css("dialog[open]")
      page.execute_script("Turbo.visit('#{learning_path}')")
      expect(page).to have_css("h1", text: "設定")
      page.go_back
      expect(page).to have_css("article", text: "三本目")
      expect(page).to have_no_css("dialog[open]")
    end

    it "動きを減らす設定では、件数をカウントアップせずに最後の数で出す" do
      sign_in
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
      enter_delete_mode
      delete_row("一本目")
      delete_row("二本目")
      expect(combo).to have_text("2 COMBO", normalize_ws: true)

      choose "読む", allow_label_click: true
      expect(find("dialog[open] [data-delete-mode-target='resultCount']").text).to eq("2")
    ensure
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    end
  end
end
