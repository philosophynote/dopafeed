# Main の行を読まずに片付ける（docs/screens/swipe.md）。左スワイプで行が消えて画面下に「元に戻す」のトーストが出て、押せば戻る、を 390×844 で通す。「興味なし」の見えるボタンは無い。
# 引く手は spec/support/system_swipe.rb。右スワイプの「保存」は spec/system/save_swipe_spec.rb
RSpec.describe "Swipe", type: :system do
  let(:now) { Time.current }
  # カード幅に対する送る閾値。view が yml から Stimulus の value で渡すので、spec も同じ所から読む
  let(:dismiss_ratio) { Dopamine.settings.dig(:swipe, :dismiss_threshold_ratio) }

  it "左スワイプで行が消えて画面下にトーストが出て未読数が減り、「元に戻す」で行が元の位置に戻る" do
    create(:article, title: "上の記事", published_at: now - 1.hour)
    create(:article, title: "関心の無い記事", published_at: now - 2.hours)
    create(:article, title: "下の記事", published_at: now - 3.hours)
    sign_in
    width = card_width("関心の無い記事")

    expect(page).to have_css("[data-unread-badge]", text: "3")
    expect(page).to have_no_button("削除")
    drag_card("関心の無い記事", from: [ width / 2, 40 ], to: [ width / 2 - width * dismiss_ratio * 1.3, 40 ])

    toast = find("#toast [data-controller='toast']", text: "1 件を削除しました")
    expect(toast).to have_button("元に戻す")
    expect(page).to have_no_css("article", text: "関心の無い記事")
    expect(page).to have_css("article", count: 2)
    expect(page).to have_css("[data-unread-badge]", text: "2")
    expect(Article.find_by(title: "関心の無い記事")).to be_dismissed
    # トーストはタブバーの上に浮き、画面の中に収まる。押す所は 44px 以上
    toast_rect = toast.evaluate_script("this.getBoundingClientRect().toJSON()")
    nav_top = find("nav[aria-label='タブバー']").evaluate_script("this.getBoundingClientRect().top")
    expect(toast_rect["bottom"]).to be <= nav_top
    expect(toast_rect["left"]).to be >= 0
    expect(toast_rect["right"]).to be <= page.evaluate_script("document.documentElement.clientWidth")
    expect(toast.find_button("元に戻す").evaluate_script("this.getBoundingClientRect().height")).to be >= 44
    screenshot!("dismissed")
    # yml に toast.visible_seconds が無ければ、トーストは消えずに残る
    sleep 1.5
    expect(page).to have_css("#toast [data-controller='toast']", wait: 0)

    click_on "元に戻す"

    expect(page).to have_css("article", count: 3)
    expect(all("article h2").map(&:text)).to eq(%w[上の記事 関心の無い記事 下の記事])
    expect(page).to have_no_css("#toast [data-controller='toast']")
    expect(page).to have_css("[data-unread-badge]", text: "3")
    expect(Article.find_by(title: "関心の無い記事")).not_to be_dismissed
  end

  it "トーストが出ている間は、一覧をスクロールしきると最後の行がトーストの上に出る" do
    create_list(:article, 12)
    create(:article, title: "最後の記事", published_at: Time.zone.local(2026, 9, 1))
    sign_in
    width = card_width(Article.order(published_at: :desc).first.title)

    drag_card(Article.order(published_at: :desc).first.title, from: [ width / 2, 40 ], to: [ width / 2 - width * dismiss_ratio * 1.3, 40 ])
    toast = find("#toast [data-controller='toast']")
    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")

    last_bottom = find("article", text: "最後の記事").evaluate_script("this.getBoundingClientRect().bottom")
    expect(last_bottom).to be <= toast.evaluate_script("this.getBoundingClientRect().top")
  end

  it "「元に戻す」が送れなかったらトーストが残り、もう一度押せば戻る" do
    create(:article, title: "戻す記事", published_at: now - 1.hour)
    calls = 0
    allow_any_instance_of(DismissalsController).to receive(:destroy).and_wrap_original do |original, *args|
      calls += 1
      calls == 1 ? original.receiver.head(:service_unavailable) : original.call(*args)
    end
    sign_in
    width = card_width("戻す記事")

    drag_card("戻す記事", from: [ width / 2, 40 ], to: [ width / 2 - width * dismiss_ratio * 1.3, 40 ])
    find("#toast").click_on("元に戻す")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました")
    expect(page).to have_no_css("article", text: "戻す記事")
    expect(Article.find_by(title: "戻す記事")).to be_dismissed

    find("#toast").click_on("元に戻す")
    expect(page).to have_css("article", text: "戻す記事")
    expect(page).to have_no_css("#toast [data-controller='toast']")
    expect(Article.find_by(title: "戻す記事")).not_to be_dismissed
  end

  it "トーストは yml の toast.visible_seconds が経つと消え、消えた後も記録は残る" do
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(toast: { visible_seconds: 1 }))
    create(:article, title: "消す記事", published_at: now - 1.hour)
    sign_in
    width = card_width("消す記事")

    drag_card("消す記事", from: [ width / 2, 40 ], to: [ width / 2 - width * dismiss_ratio * 1.3, 40 ])
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました")

    expect(page).to have_no_css("#toast [data-controller='toast']", wait: 5)
    expect(page).to have_no_css("article", text: "消す記事")
    expect(Article.find_by(title: "消す記事")).to be_dismissed
  end

  it "左へカード幅の 4 割を超えて引いて離すと、カードが流れて消え、トーストが出る" do
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
    expect(page).to have_text("1 件を削除しました")
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
    expect(page).to have_no_link("記事に遷移")
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

  it "続けざまに 2 枚流しても両方消える（送信は 1 本ずつ）。トーストは後のものに置き換わって 1 枚だけ" do
    create(:article, title: "一枚目", published_at: now - 1.hour)
    create(:article, title: "二枚目", published_at: now - 2.hours)
    sign_in
    width = card_width("一枚目")
    far = width * dismiss_ratio * 1.3

    drag_card("一枚目", from: [ width / 2, 40 ], to: [ width / 2 - far, 40 ])
    drag_card("二枚目", from: [ width / 2, 40 ], to: [ width / 2 - far, 40 ])

    # 残るトーストは 1 枚で、「元に戻す」は後に消した行を戻す。二枚目の応答が届いた印なので、記録を見る前に待つ
    second = Article.find_by!(title: "二枚目")
    expect(page).to have_css("#toast form[action='#{article_dismissal_path(second)}']", count: 1)
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました", count: 1)
    expect(page).to have_no_css("article")
    expect(page).to have_no_css("[data-unread-badge]")
    expect(Article.where.not(dismissed_at: nil).count).to eq(2)
    # 見える行が無くなったら、開き直さなくても空状態が出る
    expect(page).to have_text("全部読んだ。")
  end

  it "前の行の取り消しを、次に引いた行の応答待ちの間に押しても、次の行の送信は止まらない（送らずに次のトーストへ置き換わる）" do
    create(:article, title: "一枚目", published_at: now - 1.hour)
    create(:article, title: "二枚目", published_at: now - 2.hours)
    allow_any_instance_of(DismissalsController).to receive(:create).and_wrap_original do |original, *args|
      sleep 1
      original.call(*args)
    end
    sign_in
    width = card_width("一枚目")
    far = width * dismiss_ratio * 1.3

    drag_card("一枚目", from: [ width / 2, 40 ], to: [ width / 2 - far, 40 ])
    first = Article.find_by!(title: "一枚目")
    expect(page).to have_css("#toast form[action='#{article_dismissal_path(first)}']")
    page.execute_script("window.__starts = 0; document.addEventListener('turbo:submit-start', () => window.__starts++)")
    drag_card("二枚目", from: [ width / 2, 40 ], to: [ width / 2 - far, 40 ])
    # 二枚目が流れ終わって送信が始まってから押す（流れている間に押せば、列の先に並ぶ一枚目の取り消しが先に届くのが正しい）
    page.document.synchronize { raise Capybara::ElementNotFound, "二枚目の送信が始まらない" unless page.evaluate_script("window.__starts") >= 1 }
    find("#toast").click_on("元に戻す")

    second = Article.find_by!(title: "二枚目")
    expect(page).to have_css("#toast form[action='#{article_dismissal_path(second)}']")
    expect(page).to have_no_css("article")
    expect(second.reload).to be_dismissed
    expect(first.reload).to be_dismissed
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
    expect(page).to have_text("1 件を削除しました")
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
    expect(page).to have_text("1 件を削除しました")
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

    # 新しい触り（pointerdown）の後の click は読む。先の click が送られていれば送信は 2 本になる
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

  it "広がった行も見出しの上から左へ引けて、動くのは行だけ。広げた欄は動かず、離すと行ごと消える" do
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
    expect(page).to have_text("1 件を削除しました")
    expect(page).to have_no_link("記事に遷移")
  end
end
