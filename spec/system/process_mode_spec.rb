RSpec.describe "Process mode", type: :system do
  let(:now) { Time.current }
  let(:ratio) { Dopamine.settings.dig(:swipe, :dismiss_threshold_ratio) }

  it "「処理」に切り替えても削除ボタンは出ず、行を左へ払うと消えてトーストが出て未読数が減る。「読む」に戻すと行の「読む」が押せる状態に戻る" do
    create(:article, title: "上の記事", published_at: now - 1.hour)
    create(:article, title: "消す記事", published_at: now - 2.hours)
    create(:article, title: "下の記事", published_at: now - 3.hours)
    sign_in

    mode = find("fieldset", text: "読む")
    expect(mode).to have_checked_field("読む", visible: :all)
    expect(mode).to have_unchecked_field("処理", visible: :all)
    expect(mode).to have_no_field("削除", visible: :all)
    mode.all("label").each { |label| expect(label.evaluate_script("this.getBoundingClientRect().height")).to be >= 44 }
    expect(page).to have_no_button("削除")

    enter_process_mode
    expect(page).to have_no_button("削除")
    expect(page).to have_css("button[data-swipe-target='read'][inert]", visible: :all, count: 3)
    width = card_width("消す記事")
    drag_card("消す記事", from: [ width * 0.8, 40 ], to: [ width * 0.8 - width * ratio * 1.3, 40 ], release: false)
    expect(card_shift("消す記事")).to be < 0
    expect(rail_opacity("消す記事")).to eq(1)
    expect(swipe_rail("消す記事")[:class]).to include("swipe-armed")
    expect(swipe_rail("消す記事").text(:all)).to include("削除")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    screenshot!("delete-armed")
    drag_card("消す記事", from: [ width * 0.8, 40 ], to: [ width * 0.8 - width * ratio * 0.2, 40 ], down: false)

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
    expect(page).to have_css("button[data-swipe-target='read'][inert]", visible: :all, count: 3)
    expect(Article.find_by!(title: "消す記事")).not_to be_dismissed

    choose "読む", allow_label_click: true
    expect(page).to have_no_css("button[data-swipe-target='read'][inert]", visible: :all)
    expect(page).to have_button("「消す記事」を読む")
  end

  it "処理モードで右へ払うと保存してトーストが出る（読むモードの右と同じ向き）。左右とも閾値の手前で離すと戻り、何も送らない" do
    create(:article, title: "残す記事", published_at: now - 1.hour)
    create(:article, title: "触る記事", published_at: now - 2.hours)
    sign_in
    enter_process_mode
    page.execute_script("window.__starts = 0; document.addEventListener('turbo:submit-start', () => window.__starts++)")

    width = card_width("触る記事")
    drag_card("触る記事", from: [ width / 2, 40 ], to: [ width / 2 + width * ratio * 0.5, 40 ], slow: true)
    expect(settled_shift("触る記事")).to eq(0)
    drag_card("触る記事", from: [ width / 2, 40 ], to: [ width / 2 - width * ratio * 0.5, 40 ], slow: true)
    expect(settled_shift("触る記事")).to eq(0)
    expect(page.evaluate_script("window.__starts")).to eq(0)
    expect(find("[data-process-mode-target='combo']")).to have_text("0 COMBO", normalize_ws: true)

    drag_card("残す記事", from: [ width * 0.2, 40 ], to: [ width * 0.2 + width * ratio * 1.3, 40 ], release: false)
    expect(rail_opacity("残す記事", "saveRail")).to eq(1)
    expect(swipe_rail("残す記事", "saveRail").text(:all)).to include("保存")
    screenshot!("save-armed")
    drag_card("残す記事", from: [ width * 0.2, 40 ], to: [ width * 0.2 + width * ratio * 0.2, 40 ], down: false)

    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を保存しました")
    expect(page).to have_no_css("article", text: "残す記事")
    expect(Article.find_by!(title: "残す記事")).to be_bookmarked
    expect(Article.find_by!(title: "残す記事")).not_to be_dismissed
    expect(find("[data-process-mode-target='combo']")).to have_text("1 COMBO", normalize_ws: true)
  end

  it "続けて払うと払った分だけ消える（送信は 1 本ずつ）" do
    titles = %w[一本目 二本目 三本目 四本目]
    titles.each_with_index { |title, i| create(:article, title: title, published_at: now - (i + 1).hours) }
    sign_in
    enter_process_mode

    delete_row("一本目")
    delete_row("二本目")
    delete_row("三本目")

    expect(page).to have_css("article", count: 1)
    third = Article.find_by!(title: "三本目")
    expect(page).to have_css("#toast [data-controller='toast']", count: 1)
    expect(page).to have_css("#toast form[action='#{article_dismissal_path(third)}']")
    expect(page).to have_css("[data-unread-badge]", text: "1")
    expect(Article.where.not(dismissed_at: nil).pluck(:title)).to match_array(%w[一本目 二本目 三本目])
  end

  it "処理モードでは行を押しても広がらず読みにならない。切り替えると広げていた欄は畳む" do
    create(:article, title: "広げた記事", summary: "・要約", published_at: now - 1.hour)
    create(:article, title: "触る記事", published_at: now - 2.hours)
    sign_in
    find("article", text: "広げた記事").find_button("読む").execute_script("this.click()")
    expect(page).to have_link("記事に遷移")

    enter_process_mode
    expect(page).to have_no_link("記事に遷移")

    page.execute_script("window.__starts = 0; document.addEventListener('turbo:submit-start', () => window.__starts++)")
    native_click(find("article", text: "触る記事"))
    sleep 0.5
    expect(page.evaluate_script("window.__starts")).to eq(0)
    expect(page).to have_no_link("記事に遷移")
    expect(Article.find_by!(title: "触る記事").reading).to be_nil
  end

  it "流れ出した行をもう一度引いても送信は 1 本" do
    create(:article, title: "二度引く記事", published_at: now - 1.hour)
    create(:article, title: "残る記事", published_at: now - 2.hours)
    sign_in
    enter_process_mode
    # 応答の描画を遅らせ、流れ出した行がまだ画面にある間にもう一度引く
    page.execute_script(<<~JS)
      window.__starts = 0
      document.addEventListener("turbo:submit-start", () => window.__starts++)
      document.addEventListener("turbo:before-stream-render", (event) => {
        const render = event.detail.render
        event.detail.render = (stream) => new Promise((resolve) => setTimeout(() => resolve(render(stream)), 500))
      })
    JS

    delete_row("二度引く記事")
    delete_row("二度引く記事")

    expect(page).to have_css("#toast [data-controller='toast'][data-toast-swipe-value='1']")
    expect(page).to have_css("article", count: 1)
    expect(page.evaluate_script("window.__starts")).to eq(1)
  end

  it "「読む」の応答を待つ間に「処理」へ切り替えたら、届いた応答で行は開かない" do
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
    enter_process_mode
    page.execute_script("window.__release()")

    expect(page).to have_css("[data-swipe-target='detail'] *", visible: :all, wait: 5)
    expect(page).to have_no_link("記事に遷移")
    expect(read_button["aria-expanded"]).to eq("false")
  end

  it "画面を移って戻る・再読込すると「読む」で始まる" do
    create(:article, title: "記事", published_at: now - 1.hour)
    sign_in
    enter_process_mode

    click_on "設定"
    expect(page).to have_css("h1", text: "設定")
    page.go_back
    expect(page).to have_checked_field("読む", visible: :all)
    expect(page).to have_no_css("[data-process-mode]")

    enter_process_mode
    page.refresh
    expect(page).to have_checked_field("読む", visible: :all)
    expect(page).to have_no_css("[data-process-mode]")
  end

  it "処理モードで最後の 1 本を消しても切り替えは残り、「読む」に戻すと空状態とともに切り替えが消える。元に戻せばまた出る" do
    create(:article, title: "最後の記事", published_at: now - 1.hour)
    sign_in
    enter_process_mode

    delete_row("最後の記事")
    expect(page).to have_text("全部読んだ。")
    expect(page).to have_css("fieldset.process-mode-switch")

    choose "読む", allow_label_click: true
    find("dialog[open]").click_on "閉じる"
    expect(page).to have_no_css("fieldset.process-mode-switch")
    expect(page).to have_link("設定")

    find("#toast").click_on("元に戻す")
    expect(page).to have_css("article", text: "最後の記事")
    expect(page).to have_css("fieldset.process-mode-switch")
  end

  it "未読が 0 本ならモードの切り替えは出ない" do
    sign_in
    expect(page).to have_text("全部読んだ。")
    expect(page).to have_no_field("処理", visible: :all)
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
      find("[data-process-mode-target='combo']")
    end

    before do
      %w[一本目 二本目 三本目 四本目].each_with_index { |title, i| create(:article, title: title, published_at: now - (i + 1).hours) }
    end

    it "削除するたびにコンボが 1 増えてメロディの次の音が鳴り、元に戻すと 1 減って次は同じ音を鳴らし直す。コンボはステータスの行に重ね、行の高さも読了の「n 連続」も変えない" do
      2.times { |i| create(:reading, :completed, opened_at: now - (i + 1).minutes - 10.minutes) }
      sign_in
      status_top = find("section[aria-label='記事']").evaluate_script("this.getBoundingClientRect().top")
      expect(page).to have_css("[data-combo]", text: "2 連続", visible: :all)
      enter_process_mode
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

      undo(article_dismissal_path(Article.find_by!(title: "二本目")))
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

    it "保存も 1 件 1 コンボに数え、リザルトに削除と保存の内訳が出る。保存を元に戻すと保存から 1 引く。処理モードでは引いたときの音を鳴らさずメロディだけ" do
      sign_in
      enter_process_mode
      save_row("一本目")
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
      delete_row("二本目")
      expect(combo).to have_text("2 COMBO", normalize_ws: true)
      save_row("三本目")
      expect(combo).to have_text("3 COMBO", normalize_ws: true)
      expect(melody_notes).to eq([ 1, 2, 3 ])
      expect(sfx_log).not_to include("swipe")

      undo(article_bookmark_path(Article.find_by!(title: "三本目")))
      expect(page).to have_css("article", text: "三本目")
      expect(combo).to have_text("2 COMBO", normalize_ws: true)

      choose "読む", allow_label_click: true
      result = find("dialog[open]", text: "リザルト")
      expect(result).to have_text("2 件 処理した", normalize_ws: true)
      expect(result).to have_text("削除 1 ・ 保存 1", normalize_ws: true)
      screenshot!("breakdown")
      expect(Article.where.not(bookmarked_at: nil).pluck(:title)).to eq(%w[一本目])
      expect(Article.where.not(dismissed_at: nil).pluck(:title)).to eq(%w[二本目])
    end

    it "「読む」に戻すと、かかった時間と件数と 1 件あたりの秒数のリザルトが重なって出て、ファンファーレが鳴る。閉じると次の回は 0 から" do
      sign_in
      freeze_clock
      enter_process_mode
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
      expect(result).to have_text("削除 3 ・ 保存 0", normalize_ws: true)
      expect(sfx_log.last).to eq("fanfare")
      expect(result.find_button("閉じる").evaluate_script("this.getBoundingClientRect().height")).to be >= 44
      screenshot!("result")

      result.click_on "閉じる"
      expect(page).to have_no_css("dialog[open]")
      enter_process_mode
      expect(combo).to have_text("0 COMBO", normalize_ws: true)
    end

    it "続けて押してすぐ「読む」に戻しても、押した分がリザルトに入る。後から届いた応答は次の回のコンボに数えない" do
      sign_in
      enter_process_mode
      hold_posts
      delete_row("一本目")
      delete_row("二本目")
      delete_row("三本目")
      choose "読む", allow_label_click: true

      expect(find("dialog[open]")).to have_text("3 件", normalize_ws: true)
      find("dialog[open]").click_on "閉じる"
      enter_process_mode
      release_posts

      # 流れ出した後の行は画面の外にあっても見える要素に数えられるので、記録が揃うのを待つ
      page.document.synchronize { raise Capybara::ExpectationNotMet, "3 本の削除が届かない" unless Article.where.not(dismissed_at: nil).count == 3 }
      expect(page).to have_css("article", count: 1)
      find("#toast").click_on("元に戻す")
      expect(page).to have_css("article", count: 2)
      expect(combo).to have_text("0 COMBO", normalize_ws: true)
    end

    it "送れなかった削除はコンボから引く" do
      sign_in
      enter_process_mode
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
      expect(page).to have_no_css("li.swipe-active")
      expect(combo).to have_text("0 COMBO", normalize_ws: true)

      delete_row("一本目")
      expect(page).to have_css("article", count: 3)
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
    end

    it "待ちの上限を越えて戻った行は、先の送信の応答が届くまで払い直せない。届いた成功は数え直す" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(swipe: { submit_timeout_seconds: 1 }))
      sign_in
      enter_process_mode
      page.execute_script(<<~JS)
        const original = window.fetch
        window.fetch = (url, options) => (options?.method || "GET").toUpperCase() === "POST"
          ? new Promise((resolve) => setTimeout(() => resolve(original(url, options)), 2500))
          : original(url, options)
      JS

      save_row("一本目")
      expect(combo).to have_text("0 COMBO", normalize_ws: true, wait: 2)
      expect(page).to have_no_css("li.swipe-active")
      width = card_width("一本目")
      drag_card("一本目", from: [ width * 0.8, 40 ], to: [ width * 0.8 - width * ratio * 1.3, 40 ], release: false)
      expect(card_shift("一本目")).to eq(0)
      drag_card("一本目", from: [ width * 0.8, 40 ], to: [ width * 0.8 - width * ratio * 1.4, 40 ], down: false)
      expect(combo).to have_text("0 COMBO", normalize_ws: true)

      expect(page).to have_no_css("article", text: "一本目", wait: 5)
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
      expect(Article.find_by!(title: "一本目")).to be_bookmarked
      expect(Article.find_by!(title: "一本目")).not_to be_dismissed
      choose "読む", allow_label_click: true
      expect(find("dialog[open]")).to have_text("削除 0 ・ 保存 1", normalize_ws: true)
    end

    it "左へ引いたまま「読む」に戻してから離すと、削除はするがコンボにもリザルトにも数えない" do
      sign_in
      enter_process_mode
      width = card_width("一本目")
      drag_card("一本目", from: [ width * 0.8, 40 ], to: [ width * 0.8 - width * ratio * 1.3, 40 ], release: false)
      expect(card_shift("一本目")).to be < 0
      page.execute_script("document.querySelector('input[name=mode][value=read]').click()")
      expect(page).to have_no_css("[data-process-mode]")
      drag_card("一本目", from: [ width * 0.8, 40 ], to: [ width * 0.8, 40 ], steps: 0, down: false)

      expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました")
      expect(page).to have_no_css("article", text: "一本目")
      expect(Article.find_by!(title: "一本目")).to be_dismissed
      expect(sfx_log).not_to include("melody")
    end

    it "読むモードで閾値を越えて swipe が鳴った引きは、「処理」に切り替えてから離しても削除するだけで、コンボに数えず melody を重ねない" do
      sign_in
      width = card_width("一本目")
      drag_card("一本目", from: [ width * 0.8, 40 ], to: [ width * 0.8 - width * ratio * 1.3, 40 ], release: false)
      expect(sfx_log).to eq([ "swipe" ])
      page.execute_script("document.querySelector('input[name=mode][value=process]').click()")
      expect(page).to have_css("[data-process-mode]")
      drag_card("一本目", from: [ width * 0.8, 40 ], to: [ width * 0.8, 40 ], steps: 0, down: false)

      expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました")
      expect(Article.find_by!(title: "一本目")).to be_dismissed
      expect(combo).to have_text("0 COMBO", normalize_ws: true)
      expect(sfx_log).to eq([ "swipe" ])
    end

    it "待ちの上限を越えて失敗に見えた削除も、後から成功が届けばコンボに数え直す" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(swipe: { submit_timeout_seconds: 1 }))
      sign_in
      enter_process_mode
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
      enter_process_mode
      choose "読む", allow_label_click: true
      sleep 0.3
      expect(page).to have_no_css("dialog[open]")

      enter_process_mode
      delete_row("一本目")
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
      advance_clock(9_500)
      choose "読む", allow_label_click: true
      result = find("dialog[open]")
      expect(result).to have_text("1 件 処理した", normalize_ws: true)
      expect(result).to have_text("9 秒", normalize_ws: true)
      expect(result).to have_no_text("分")
    end

    it "リザルトは枠の外を押すと閉じ、枠の中の余白を押しても閉じない。開いたまま画面を移って戻ると閉じている" do
      sign_in
      enter_process_mode
      delete_row("一本目")
      expect(combo).to have_text("1 COMBO", normalize_ws: true)
      choose "読む", allow_label_click: true
      result = find("dialog[open]")

      rect = result.evaluate_script("this.getBoundingClientRect().toJSON()")
      page.driver.browser.action.move_to_location(rect["left"] + rect["width"] / 2, rect["top"] + 4).click.perform
      expect(page).to have_css("dialog[open]")
      page.driver.browser.action.move_to_location(rect["left"] / 2, rect["top"] / 2).click.perform
      expect(page).to have_no_css("dialog[open]")

      enter_process_mode
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
      enter_process_mode
      delete_row("一本目")
      delete_row("二本目")
      expect(combo).to have_text("2 COMBO", normalize_ws: true)

      choose "読む", allow_label_click: true
      expect(find("dialog[open] [data-process-mode-target='resultCount']").text).to eq("2")
    ensure
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    end
  end

  context "コンボの節目" do
    def sfx_log
      page.evaluate_script('JSON.parse(sessionStorage.getItem("sfx-log") || "[]")')
    end

    def melody_notes
      levels = page.evaluate_script('JSON.parse(sessionStorage.getItem("sfx-log-levels") || "[]")')
      sfx_log.zip(levels).filter_map { |cue, level| level if cue == "melody" }
    end

    def band
      find("[data-process-mode-target='band']")
    end

    def cheer
      find("[data-process-mode-target='cheer']", visible: :all)
    end

    # 行は上から順に消す。元に戻した行は飛ばしたままでよい（どの行でも 1 コンボ）
    def delete_until(count)
      @deleted ||= 0
      count.times { delete_row(format("記事%02d", @deleted += 1)) }
    end

    def with_milestones(small:, large:)
      settings = Dopamine.settings.deep_merge(delete_mode: { combo_small_every: small, combo_large_every: large })
      allow(Dopamine).to receive(:settings).and_return(settings)
    end

    let(:small) { Dopamine.settings.dig(:delete_mode, :combo_small_every) }
    let(:large) { Dopamine.settings.dig(:delete_mode, :combo_large_every) }

    before do
      12.times { |i| create(:article, title: "記事#{format("%02d", i + 1)}", published_at: now - (i + 1).hours) }
    end

    it "yml の節目（5 で小、10 で大）に届くと、小は帯が光って「NICE!」、大は帯が虹色になり火花が散って「GREAT!!」が出る。節目でもメロディは鳴らす" do
      expect([ small, large ]).to eq([ 5, 10 ])
      sign_in
      enter_process_mode

      delete_until(small - 1)
      expect(band).to have_text("#{small - 1} COMBO", normalize_ws: true)
      expect(cheer.text).to eq("")
      expect(sfx_log).not_to include("combo_nice")

      delete_until(1)
      expect(band).to have_text("#{small} COMBO", normalize_ws: true)
      expect(cheer).to have_text("NICE!")
      expect(band[:class]).to include("is-nice")
      expect(sfx_log.last(2)).to eq(%w[melody combo_nice])
      expect(melody_notes.last).to eq(small)
      screenshot!("nice")

      delete_until(1)
      expect(band).to have_text("#{small + 1} COMBO", normalize_ws: true)
      expect(cheer.text(:all)).to eq("")

      delete_until(large - small - 1)
      expect(band).to have_text("#{large} COMBO", normalize_ws: true)
      expect(cheer).to have_text("GREAT!!")
      expect(band[:class]).to include("is-great")
      expect(page).to have_css("[data-process-mode-target='burst'].is-bursting span", visible: :all, minimum: 1)
      expect(sfx_log.last(2)).to eq(%w[melody combo_great])
      expect(sfx_log.count("combo_nice")).to eq(1)
      expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "火花で横スクロールが出ている"
      screenshot!("great")

      delete_until(1)
      expect(band).to have_text("#{large + 1} COMBO", normalize_ws: true)
      expect(band[:class]).to include("is-great")
      expect(cheer.text(:all)).to eq("")
      expect(sfx_log.last).to eq("melody")
    end

    it "節目は繰り返す。小と大が重なる数では大だけを出す" do
      with_milestones(small: 2, large: 4)
      sign_in
      enter_process_mode

      delete_until(2)
      expect(cheer).to have_text("NICE!")
      delete_until(2)
      expect(cheer).to have_text("GREAT!!")
      expect(sfx_log.count("combo_nice")).to eq(1)
      delete_until(2)
      expect(band).to have_text("6 COMBO", normalize_ws: true)
      expect(cheer).to have_text("NICE!")
      expect(band[:class]).to include("is-great")
      delete_until(2)
      expect(cheer).to have_text("GREAT!!")
      expect(sfx_log.count("combo_nice")).to eq(2)
      expect(sfx_log.count("combo_great")).to eq(2)
    end

    it "元に戻して節目の手前に下がってから届き直しても、同じ節目の演出は出し直さない" do
      with_milestones(small: 2, large: 4)
      sign_in
      enter_process_mode

      delete_until(2)
      expect(cheer).to have_text("NICE!")
      undo(article_dismissal_path(Article.find_by!(title: "記事02")))
      expect(band).to have_text("1 COMBO", normalize_ws: true)
      delete_until(1)
      expect(band).to have_text("2 COMBO", normalize_ws: true)
      expect(sfx_log.count("combo_nice")).to eq(1)
      expect(sfx_log.last).to eq("melody")
    end

    it "「読む」に戻してまた「処理」に入ると、帯は黒に戻り、節目は 0 から数え直す" do
      with_milestones(small: 2, large: 4)
      sign_in
      enter_process_mode
      delete_until(4)
      expect(band[:class]).to include("is-great")

      choose "読む", allow_label_click: true
      find("dialog[open]").click_on "閉じる"
      enter_process_mode

      expect(band[:class]).not_to include("is-great")
      expect(cheer.text).to eq("")
      delete_until(2)
      expect(cheer).to have_text("NICE!")
      expect(sfx_log.count("combo_nice")).to eq(2)
    end

    it "演出の最中でも次の行を払えて、一覧の位置は動かない" do
      with_milestones(small: 2, large: 4)
      sign_in
      enter_process_mode
      list_top = find("section[aria-label='記事']").evaluate_script("this.getBoundingClientRect().top")

      delete_until(4)
      expect(cheer).to have_text("GREAT!!")
      delete_until(1)

      expect(band).to have_text("5 COMBO", normalize_ws: true)
      expect(find("section[aria-label='記事']").evaluate_script("this.getBoundingClientRect().top")).to eq(list_top)
      expect(page).to have_css("#toast form[action='#{article_dismissal_path(Article.find_by!(title: "記事05"))}']")
      expect(Article.where.not(dismissed_at: nil).count).to eq(5)
    end

    it "動きを減らす設定では、文字と音は出るが帯も文字も火花も動かない" do
      with_milestones(small: 2, large: 4)
      sign_in
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
      enter_process_mode

      delete_until(2)
      expect(cheer).to have_text("NICE!")
      expect(sfx_log).to include("combo_nice")
      expect(band.evaluate_script("getComputedStyle(this).animationName")).to eq("none")
      expect(cheer.evaluate_script("getComputedStyle(this).animationName")).to eq("none")

      delete_until(2)
      expect(cheer).to have_text("GREAT!!")
      expect(sfx_log).to include("combo_great")
      expect(band.evaluate_script("getComputedStyle(this).backgroundImage")).to include("linear-gradient")
      expect(band.evaluate_script("getComputedStyle(this).animationName")).to eq("none")
      expect(cheer.evaluate_script("getComputedStyle(this).animationName")).to eq("none")
      expect(page).to have_no_css("[data-process-mode-target='burst'].is-bursting", visible: :all)
    ensure
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    end

    it "待ちの上限を越えて後から届いた成功で数え直したときは、押していないので節目の演出を出さない" do
      settings = Dopamine.settings.deep_merge(delete_mode: { combo_small_every: 1, combo_large_every: 0 }, swipe: { submit_timeout_seconds: 1 })
      allow(Dopamine).to receive(:settings).and_return(settings)
      sign_in
      enter_process_mode
      page.execute_script(<<~JS)
        const original = window.fetch
        window.fetch = (url, options) => (options?.method || "GET").toUpperCase() === "POST"
          ? new Promise((resolve) => setTimeout(() => resolve(original(url, options)), 2500))
          : original(url, options)
      JS

      delete_until(1)
      expect(cheer).to have_text("NICE!")
      expect(band).to have_text("0 COMBO", normalize_ws: true, wait: 2)
      expect(page).to have_css("article", count: 11, wait: 5)
      expect(band).to have_text("1 COMBO", normalize_ws: true)
      expect(cheer.text(:all)).to eq("")
      expect(sfx_log.count("combo_nice")).to eq(1)
    end

    it "yml に節目の鍵が無ければ、節目の演出は出ない" do
      settings = Dopamine.settings.deep_dup
      settings.delete(:delete_mode)
      allow(Dopamine).to receive(:settings).and_return(settings)
      sign_in
      enter_process_mode

      delete_until(10)
      expect(band).to have_text("10 COMBO", normalize_ws: true)
      expect(cheer.text).to eq("")
      expect(band[:class]).not_to include("is-nice", "is-great")
      expect(sfx_log).not_to include("combo_nice", "combo_great")
    end
  end
end
