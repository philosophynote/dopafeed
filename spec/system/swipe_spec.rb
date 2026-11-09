RSpec.describe "Swipe", type: :system do
  let(:now) { Time.current }
  let(:dismiss_ratio) { Dopamine.settings.dig(:swipe, :dismiss_threshold_ratio) }

  it "左スワイプで行が帯に替わり未読数が減り、「元に戻す」で行が戻る" do
    create(:article, title: "関心の無い記事", published_at: now - 1.hour)
    create(:article, title: "読みたい記事", published_at: now - 2.hours)
    sign_in
    width = card_width("関心の無い記事")

    expect(page).to have_css("[data-unread-badge]", text: "2")
    expect(page).to have_no_button("削除")
    drag_card("関心の無い記事", from: [ width / 2, 40 ], to: [ width / 2 - width * dismiss_ratio * 1.3, 40 ])

    # 帯は見出しだけを省略するために 3 つの span に分かれ、見える文字は改行を挟んで読まれる。文として一致させず、帯の中に見出しがあることを見る
    strip = find("li", text: "を削除した")
    expect(strip).to have_text("関心の無い記事")
    expect(strip).to have_button("元に戻す")
    expect(page).to have_css("article", count: 1)
    expect(page).to have_css("[data-unread-badge]", text: "1")
    expect(Article.find_by(title: "関心の無い記事")).to be_dismissed
    screenshot!("dismissed")

    click_on "元に戻す"

    expect(page).to have_css("article", count: 2)
    expect(page).to have_no_text("を削除した")
    expect(page).to have_css("[data-unread-badge]", text: "2")
    expect(Article.find_by(title: "関心の無い記事")).not_to be_dismissed
  end

  it "左へカード幅の 4 割を超えて引いて離すと、カードが流れて帯に替わる" do
    create(:article, title: "飛ばす記事", published_at: now - 1.hour)
    create(:article, title: "残す記事", published_at: now - 2.hours)
    sign_in
    width = card_width("飛ばす記事")

    pull = width * dismiss_ratio * 0.6
    drag_card("飛ばす記事", from: [ width / 2, 40 ], to: [ width / 2 - pull, 40 ], release: false)
    expect(card_shift("飛ばす記事")).to be < -(pull * 0.8)
    expect(rail_opacity("飛ばす記事")).to be > 0.3
    rail = find("article", text: "飛ばす記事").find(:xpath, "..").find("[data-swipe-target='rail']", visible: :all)
    expect(rail).to have_css("svg", visible: :all)
    expect(rail).to have_text("削除", normalize_ws: true)
    expect(rail.evaluate_script("this.getBoundingClientRect().width")).to be_within(16).of(pull)
    expect(rail[:class]).not_to include("swipe-armed")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "引いている間に横スクロールが出ている"
    screenshot!("swiping")

    drag_card("飛ばす記事", from: [ width / 2 - pull, 40 ], to: [ width / 2 - width * dismiss_ratio * 1.1, 40 ], release: false)
    expect(rail[:class]).to include("swipe-armed")
    screenshot!("armed")
    drag_card("飛ばす記事", from: [ width / 2 - width * dismiss_ratio * 1.1, 40 ], to: [ width / 2 - width * dismiss_ratio * 1.3, 40 ])
    expect(page).to have_text("を削除した")
    expect(page).to have_css("article", count: 1)
    expect(page).to have_css("[data-unread-badge]", text: "1")
    expect(Article.find_by(title: "飛ばす記事")).to be_dismissed
    expect(Article.find_by(title: "残す記事")).not_to be_dismissed
  end

  it "閾値に届かずに離すと戻り、縦の動きと左端からの触りは拾わない" do
    create(:article, title: "戻る記事", published_at: now - 1.hour)
    sign_in
    width = card_width("戻る記事")

    drag_card("戻る記事", from: [ width / 2, 40 ], to: [ width / 2 - width * dismiss_ratio * 0.5, 40 ])
    expect(page).to have_css("article", text: "戻る記事")
    expect(settled_shift("戻る記事")).to eq(0)
    expect(rail_opacity("戻る記事")).to eq(0)

    read_button = find("article", text: "戻る記事").find_button("読む")
    drag_card("戻る記事", from: [ width / 2, 40 ], to: [ width / 2 - width * dismiss_ratio * 0.6, 40 ], on: read_button, release: false)
    expect(card_shift("戻る記事")).to be < 0
    read_button.execute_script(<<~JS)
      const rect = this.getBoundingClientRect()
      this.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, pointerId: 7, pointerType: "touch", isPrimary: true, clientX: rect.left + 40, clientY: rect.top + 40 }))
    JS
    expect(settled_shift("戻る記事")).to eq(0)
    page.execute_script("window.__submits = 0; document.addEventListener('turbo:submit-start', () => window.__submits++)")
    read_button.execute_script("this.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 }))")
    expect(page).to have_no_link("記事に遷移")
    expect(Article.find_by(title: "戻る記事").reading).to be_nil

    drag_card("戻る記事", from: [ width / 2, 20 ], to: [ width / 2 - 30, 160 ])
    expect(settled_shift("戻る記事")).to eq(0)

    # 画面の左端（iOS の「戻る」の帯）から始まった触りは拾わない。カードの左端は画面から 16px なので x = -10 が画面の 6px
    drag_card("戻る記事", from: [ -10, 40 ], to: [ -10 - width * dismiss_ratio * 1.5, 40 ])
    expect(settled_shift("戻る記事")).to eq(0)

    expect(page).to have_css("article", count: 1)
    expect(Article.find_by(title: "戻る記事")).not_to be_dismissed
  end

  it "続けざまに 2 枚流しても両方が帯になる（送信は 1 本ずつ）" do
    create(:article, title: "一枚目", published_at: now - 1.hour)
    create(:article, title: "二枚目", published_at: now - 2.hours)
    sign_in
    width = card_width("一枚目")
    far = width * dismiss_ratio * 1.3

    drag_card("一枚目", from: [ width / 2, 40 ], to: [ width / 2 - far, 40 ])
    drag_card("二枚目", from: [ width / 2, 40 ], to: [ width / 2 - far, 40 ])

    expect(page).to have_css("li", text: "を削除した", count: 2)
    expect(page).to have_no_css("article")
    expect(page).to have_no_css("[data-unread-badge]")
    expect(Article.where.not(dismissed_at: nil).count).to eq(2)
  end

  it "送れなかったらカードが戻り、もう一度引ける" do
    create(:article, title: "圏外の記事", published_at: now - 1.hour)
    sign_in
    width = card_width("圏外の記事")
    far = width * dismiss_ratio * 1.3

    page.execute_script("window.__fetch = window.fetch; window.fetch = () => Promise.reject(new TypeError('offline'))")
    drag_card("圏外の記事", from: [ width / 2, 40 ], to: [ width / 2 - far, 40 ])
    expect(page).to have_css("article", text: "圏外の記事")
    expect(settled_shift("圏外の記事")).to eq(0)
    expect(Article.find_by(title: "圏外の記事")).not_to be_dismissed

    page.execute_script("window.fetch = window.__fetch")
    drag_card("圏外の記事", from: [ width / 2, 40 ], to: [ width / 2 - far, 40 ])
    expect(page).to have_text("を削除した")
    expect(Article.find_by(title: "圏外の記事")).to be_dismissed
  end

  it "送信の応答を待つ間に画面を離れて戻っても、次のスワイプは送れる" do
    create(:article, title: "待たせる記事", published_at: now - 1.hour)
    create(:article, title: "次の記事", published_at: now - 2.hours)
    sign_in
    width = card_width("待たせる記事")
    far = width * dismiss_ratio * 1.3

    # POST だけ応答も中断も返さない fetch にして、送信中のまま Turbo で設定へ移る（画面の移動は GET なので通す）
    page.execute_script(<<~JS)
      window.__fetch = window.fetch
      window.fetch = (url, options) => (options?.method || "GET").toUpperCase() === "POST" ? new Promise(() => {}) : window.__fetch(url, options)
    JS
    drag_card("待たせる記事", from: [ width / 2, 40 ], to: [ width / 2 - far, 40 ])
    # 流れ終わって送信が始まる（Turbo が form に aria-busy を付ける）のを待ってから離れる
    expect(page).to have_css("form[aria-busy='true']", visible: :all)
    click_on "設定"
    expect(page).to have_css("h1", text: "設定")
    click_on "戻る"
    expect(page).to have_css("article", text: "次の記事")

    page.execute_script("window.fetch = window.__fetch")
    drag_card("次の記事", from: [ width / 2, 40 ], to: [ width / 2 - far, 40 ])
    expect(page).to have_text("を削除した")
    expect(Article.find_by(title: "次の記事")).to be_dismissed
  end

  it "引いて戻した直後の click は送らず、次に触れて離せば 1 本だけ送って行を広げる" do
    create(:article, title: "迷う記事", published_at: now - 1.hour)
    sign_in
    width = card_width("迷う記事")
    read_button = find("article", text: "迷う記事").find_button("読む")

    drag_card("迷う記事", from: [ width / 2, 40 ], to: [ width / 2 - width * dismiss_ratio * 0.5, 40 ], on: read_button)
    expect(settled_shift("迷う記事")).to eq(0)
    page.execute_script("window.__submits = 0; document.addEventListener('turbo:submit-start', () => window.__submits++)")
    click = "this.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 }))"
    read_button.execute_script(click)

    read_button.execute_script("this.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerId: 8, isPrimary: true, button: 0, clientX: 200, clientY: 10 }))")
    read_button.execute_script(click)
    expect(page).to have_link("記事に遷移")
    expect(page.evaluate_script("window.__submits")).to eq(1)
  end

  it "続けて 2 回押しても送信は 1 本。送れなかったらもう一度押して広げられる" do
    article = create(:article, title: "押す記事", published_at: now - 1.hour)
    sign_in
    read_button = find("article", text: "押す記事").find_button("読む")

    page.execute_script("window.__fetch = window.fetch; window.fetch = () => Promise.reject(new TypeError('offline'))")
    read_button.execute_script("this.click()")
    expect(page).to have_no_css("form[aria-busy='true']", visible: :all)
    expect(article.reload.reading).to be_nil

    page.execute_script(<<~JS)
      window.fetch = window.__fetch
      window.__submits = 0
      document.addEventListener("turbo:submit-start", () => window.__submits++)
    JS
    read_button.execute_script("this.click(); this.click()")
    expect(page).to have_link("記事に遷移", count: 1)
    expect(page.evaluate_script("window.__submits")).to eq(1)
    expect(article.reload.reading).to be_present
  end

  it "「読む」の応答が来ないまま待ちの上限を過ぎたら送信を止め、押し直して読める" do
    short = Dopamine.settings.deep_dup
    short[:swipe][:submit_timeout_seconds] = 1
    allow(Dopamine).to receive(:settings).and_return(short)
    article = create(:article, title: "待つ記事", published_at: now - 1.hour)
    sign_in
    read_button = find("article", text: "待つ記事").find_button("読む")

    # POST だけ応答を返さず、中断されたら AbortError で終わる fetch（圏外で返事が来ない状態）
    page.execute_script(<<~JS)
      window.__fetch = window.fetch
      window.fetch = (url, options) => (options?.method || "GET").toUpperCase() === "POST"
        ? new Promise((_, reject) => options.signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError"))))
        : window.__fetch(url, options)
    JS
    read_button.execute_script("this.click()")
    expect(page).to have_css("button[data-swipe-target='read'][disabled]", visible: :all)
    expect(page).to have_no_css("button[data-swipe-target='read'][disabled]", visible: :all, wait: 5)

    page.execute_script("window.fetch = window.__fetch")
    read_button.execute_script("this.click()")
    expect(page).to have_link("記事に遷移")
    expect(article.reload.reading).to be_present
  end

  it "広がった行も見出しの上から左へ引けて、動くのは行だけ。広げた欄は動かず、離すと行ごと帯に替わる" do
    create(:article, title: "広げた記事", summary: "・広げた要約", published_at: now - 1.hour)
    sign_in
    find("article", text: "広げた記事").find_button("読む").execute_script("this.click()")
    expect(page).to have_link("記事に遷移")
    width = card_width("広げた記事")
    detail_left = page.evaluate_script("document.querySelector('[data-swipe-target=detail]').getBoundingClientRect().left")
    rail_height = find("article", text: "広げた記事").evaluate_script("this.parentElement.querySelector('[data-swipe-target=rail]').getBoundingClientRect().height")

    drag_card("広げた記事", from: [ width / 2, 30 ], to: [ width / 2 - width * dismiss_ratio * 0.6, 30 ], release: false)
    expect(card_shift("広げた記事")).to be < 0
    expect(page.evaluate_script("document.querySelector('[data-swipe-target=detail]').getBoundingClientRect().left")).to eq(detail_left)
    expect(rail_height).to be <= find("article", text: "広げた記事").evaluate_script("this.getBoundingClientRect().height")
    page.execute_script(<<~JS)
      const card = document.querySelector("article")
      const rect = card.getBoundingClientRect()
      card.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, pointerId: 7, pointerType: "touch", isPrimary: true, clientX: rect.left + 10, clientY: rect.top + 30 }))
    JS
    expect(settled_shift("広げた記事")).to eq(0)

    drag_card("広げた記事", from: [ width / 2, 30 ], to: [ width / 2 - width * dismiss_ratio * 1.5, 30 ])
    expect(page).to have_text("を削除した")
    expect(page).to have_no_link("記事に遷移")
  end
end
