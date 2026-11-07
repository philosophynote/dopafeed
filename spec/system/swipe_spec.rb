# Main の行を読まずに片付ける（docs/screens/swipe.md）。左スワイプで帯に替わり、「元に戻す」で戻る、を 390×844 で通す。「興味なし」の見えるボタンは無い。
# スワイプは Pointer Events を JS から送って作る（system spec は touch を切っている。spec/support/system_click.rb）。
# 本物の指との違いは座標の出どころだけで、横か縦かの判定・閾値・form の送信は同じ道を通る
RSpec.describe "Swipe", type: :system do
  let(:now) { Time.current }
  # カード幅に対する送る閾値。view が yml から Stimulus の value で渡すので、spec も同じ所から読む
  let(:dismiss_ratio) { Dopamine.settings.dig(:swipe, :dismiss_threshold_ratio) }

  # カードの上で pointer を押し、動かし、離す。x / y はカードの左上からの CSS px、steps は途中の pointermove の数。
  # on を渡すと、その要素の上で始めた触りになる（イベントはカードまで bubbling する）
  def drag_card(title, from:, to:, steps: 4, release: true, on: nil)
    card = find("article", text: title)
    page.execute_script(<<~JS, card.native, on&.native, from, to, steps, release)
      const [card, origin, from, to, steps, release] = arguments
      const rect = card.getBoundingClientRect()
      const fire = (type, x, y) => (origin || card).dispatchEvent(new PointerEvent(type, {
        bubbles: true, cancelable: true, composed: true,
        pointerId: 7, pointerType: "touch", isPrimary: true, button: type === "pointermove" ? -1 : 0, buttons: 1,
        clientX: rect.left + x, clientY: rect.top + y
      }))
      fire("pointerdown", from[0], from[1])
      for (let i = 1; i <= steps; i++) {
        fire("pointermove", from[0] + (to[0] - from[0]) * i / steps, from[1] + (to[1] - from[1]) * i / steps)
      }
      if (release) fire("pointerup", to[0], to[1])
    JS
  end

  def card_width(title)
    find("article", text: title).evaluate_script("this.getBoundingClientRect().width")
  end

  def card_shift(title)
    find("article", text: title).evaluate_script("new DOMMatrixReadOnly(getComputedStyle(this).transform).m41")
  end

  def rail_opacity(title)
    find("article", text: title).evaluate_script("parseFloat(getComputedStyle(this.parentElement.querySelector('[data-swipe-target=rail]')).opacity)")
  end

  # 離した後の戻りは transition（200ms）で動くので、止まるまで待ってから位置を見る
  def settled_shift(title)
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until card_shift(title).zero? }
    card_shift(title)
  rescue Timeout::Error
    card_shift(title)
  end

  it "左スワイプで行が帯に替わり未読数が減り、「元に戻す」で行が戻る" do
    create(:article, title: "関心の無い記事", published_at: now - 1.hour)
    create(:article, title: "読みたい記事", published_at: now - 2.hours)
    sign_in
    width = card_width("関心の無い記事")

    expect(page).to have_text("未読 2 件")
    expect(page).to have_no_button("削除")
    drag_card("関心の無い記事", from: [ width / 2, 40 ], to: [ width / 2 - width * dismiss_ratio * 1.3, 40 ])

    # 帯は見出しだけを省略するために 3 つの span に分かれ、見える文字は改行を挟んで読まれる。文として一致させず、帯の中に見出しがあることを見る
    strip = find("li", text: "を削除した")
    expect(strip).to have_text("関心の無い記事")
    expect(strip).to have_button("元に戻す")
    expect(page).to have_css("article", count: 1)
    expect(page).to have_text("未読 1 件")
    expect(page).to have_css("[data-unread-badge]", text: "1")
    expect(Article.find_by(title: "関心の無い記事")).to be_dismissed
    screenshot!("dismissed")

    click_on "元に戻す"

    expect(page).to have_css("article", count: 2)
    expect(page).to have_no_text("を削除した")
    expect(page).to have_text("未読 2 件")
    expect(Article.find_by(title: "関心の無い記事")).not_to be_dismissed
  end

  it "左へカード幅の 4 割を超えて引いて離すと、カードが流れて帯に替わる。右へ引いても動かない" do
    create(:article, title: "飛ばす記事", published_at: now - 1.hour)
    create(:article, title: "残す記事", published_at: now - 2.hours)
    sign_in
    width = card_width("飛ばす記事")

    # 途中で止めると指に付いてきて、右側のレールが見える
    pull = width * dismiss_ratio * 0.6
    drag_card("飛ばす記事", from: [ width / 2, 40 ], to: [ width / 2 - pull, 40 ], release: false)
    expect(card_shift("飛ばす記事")).to be < -(pull * 0.8)
    expect(rail_opacity("飛ばす記事")).to be > 0.3
    # 引いた幅だけ右から赤い丸型の背景が伸び、ゴミ箱のアイコンと「削除」が出る（閾値の手前ではまだ薄い色）
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
    expect(page).to have_text("未読 1 件")
    expect(Article.find_by(title: "飛ばす記事")).to be_dismissed
    expect(Article.find_by(title: "残す記事")).not_to be_dismissed

    # 右へ引いてもカードは動かず、離しても何も起きない
    drag_card("残す記事", from: [ width / 2, 40 ], to: [ width / 2 + width * dismiss_ratio * 1.5, 40 ])
    expect(settled_shift("残す記事")).to eq(0)
    expect(page).to have_css("article", count: 1)
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

    # 行全体は「読む」のボタン。その上から始めた触りも引け、引いて戻した後に来る click では読まない
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
    expect(page).to have_no_css("[role='dialog'][aria-label='ルーレット']")
    expect(Article.find_by(title: "戻る記事").reading).to be_nil

    # 縦に動いた触りはスクロールに任せ、横へ少し流れてもカードは動かない
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
    expect(page).to have_text("未読 0 件")
    expect(Article.where.not(dismissed_at: nil).count).to eq(2)
  end

  it "送れなかったらカードが戻り、もう一度引ける" do
    create(:article, title: "圏外の記事", published_at: now - 1.hour)
    sign_in
    width = card_width("圏外の記事")
    far = width * dismiss_ratio * 1.3

    # Turbo の送信は fetch なので、落として圏外を作る
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

  it "引いて戻した直後の click は送らず、次に触れて離せば 1 本だけ送って読む" do
    create(:article, title: "迷う記事", published_at: now - 1.hour)
    sign_in
    width = card_width("迷う記事")
    read_button = find("article", text: "迷う記事").find_button("読む")

    drag_card("迷う記事", from: [ width / 2, 40 ], to: [ width / 2 - width * dismiss_ratio * 0.5, 40 ], on: read_button)
    expect(settled_shift("迷う記事")).to eq(0)
    page.execute_script("window.__submits = 0; document.addEventListener('turbo:submit-start', () => window.__submits++)")
    click = "this.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 }))"
    read_button.execute_script(click)

    # 新しい触り（pointerdown）の後の click は読む。先の click が送られていれば送信は 2 本になる
    read_button.execute_script("this.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerId: 8, isPrimary: true, button: 0, clientX: 200, clientY: 10 }))")
    read_button.execute_script(click)
    expect(page).to have_css("[role='dialog'][aria-label='ルーレット']")
    expect(page.evaluate_script("window.__submits")).to eq(1)
  end

  it "続けて 2 回押してもルーレットは 1 つ。送れなかったらもう一度押して読める" do
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
    expect(page).to have_css("[role='dialog'][aria-label='ルーレット']", count: 1)
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
    expect(page).to have_css("[role='dialog'][aria-label='ルーレット']")
    expect(article.reload.reading).to be_present
  end
end
