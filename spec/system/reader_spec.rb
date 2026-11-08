# 読む → Roulette → Reader のカード（Main の行は下に広がるので、入口は Saved の行。ADR 0019） → 「記事を開く」で元サイトを別窓に開く → 戻ると判定と次の記事が継ぎ足される、を 390×844 で通す。
# iPhone のホーム画面アプリではシートで開くが、headless Chrome では別窓（タブ）になる。出た合図は visibilitychange の hidden、戻りは visible か focus。
# 滞在は travel_to ではなく opened_at を書き換えて作る（ブラウザの時計とずれないように）
RSpec.describe "Reader", type: :system do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:common) { Dopamine.rarity_names.first }
  let(:now) { Time.current }
  # 元サイトの代わり。外へは出ないので、このアプリの /up（ヘルスチェック）を開く。url は記事ごとに一意なので問い合わせ文字列で分ける
  def source_url(name)
    "#{Capybara.current_session.server.base_url}/up?#{name}"
  end

  before { allow(RarityDraw).to receive(:draw).and_return(common) }

  def no_horizontal_scroll?
    page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
  end

  def make_dwell(reading, seconds)
    reading.reload.update_columns(opened_at: Time.current - seconds)
  end

  # 「記事を開く」の POST /readings/:id/start は fetch で送るので、届いて opened_at が書き換わるまで待つ
  def wait_for_start(reading, since:)
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until reading.reload.opened_at > since }
  end

  # 元サイトを別窓に開き、閉じて Reader に戻る。滞在は別窓にいる間に作る（Reader に戻った瞬間に判定が走るので）
  def open_source_and_return(reading)
    since = reading.reload.opened_at
    reader = current_window
    source = window_opened_by { find_link("記事を開く", href: reading.article.url).click }
    within_window(source) do
      expect(page).to have_current_path("/up", ignore_query: true)
      wait_for_start(reading, since: since)
      yield if block_given?
    end
    source.close
    switch_to_window(reader)
  end

  it "記事を開いて戻ると、判定と次の記事のカードが下に継ぎ足され、続けて読める" do
    first = create(:article, title: "最初の記事", url: source_url("first"), published_at: now - 1.hour, summary: "・最初の要約\n・二\n・三")
    second = create(:article, title: "次の記事", url: source_url("second"), published_at: now - 2.hours, summary: "・次の要約")
    sign_in

    read_from_saved(first)
    expect(page).to have_text("・最初の要約")
    expect(page).to have_link("記事を開く", href: first.url)
    expect(page).to have_no_button("読み終えた")
    expect(no_horizontal_scroll?).to be(true), "カードが横にはみ出している"
    screenshot!("card")

    open_source_and_return(first.reading) { make_dwell(first.reading, threshold + 5) }

    expect(page).to have_css("section[aria-label='判定']", text: "通常カードを手に入れた！")
    # カードは裏からめくれて表になる（めくり終わるまで待ってから次へ）
    card = find("section[aria-label='判定'] li.card-reveal")
    expect(card).to have_css("h3", text: "最初の記事")
    page.evaluate_async_script("const done = arguments[0]; Promise.all(document.querySelector('li.card-reveal').getAnimations().map((a) => a.finished)).then(() => done(true))")
    expect(page.evaluate_script("getComputedStyle(document.querySelector('li.card-reveal')).transform")).to eq("none").or eq("matrix(1, 0, 0, 1, 0, 0)")
    expect(page).to have_no_css("[data-controller='reveal']") # 通常は全画面にしない
    expect(page).to have_text("今日のゴール 1 / #{goal_articles}")
    expect(page).to have_css("h1", text: "次の記事")
    expect(page).to have_current_path(read_article_path(first))
    expect(first.reload.reading).to be_completed
    expect(page).to have_no_button("読み終えた") # 継ぎ足された次のカードも、開くまでは隠す
    screenshot!("divider")

    # 次の記事はすぐ戻ると未完。未読が尽きたら「全部読んだ」
    open_source_and_return(second.reload.reading)
    expect(page).to have_css("section[aria-label='判定']", text: "カードにならなかった")
    expect(page).to have_text("全部読んだ")
    expect(second.reading.reload).not_to be_completed
    expect(no_horizontal_scroll?).to be(true)

    click_on "閉じる", match: :first
    expect(page).to have_current_path(root_path)
    expect(page).to have_no_text("最初の記事")
    expect(page).to have_text("次の記事")
  end

  it "prefers-reduced-motion ならカードはめくらずに表で出る" do
    article = create(:article, title: "動かさない記事", url: source_url("still"), summary: "・一")
    sign_in
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])

    read_from_saved(article)
    open_source_and_return(article.reading) { make_dwell(article.reading, threshold + 5) }

    expect(page).to have_css("section[aria-label='判定'] li.card-reveal h3", text: "動かさない記事")
    expect(page.evaluate_script("getComputedStyle(document.querySelector('li.card-reveal')).animationName")).to eq("none")
    expect(page.evaluate_script("getComputedStyle(document.querySelector('li.card-reveal')).transform")).to eq("none")
  end

  it "OGP 画像のある記事は Reader のカードの上端に出し、無い記事には枠を出さない" do
    article = create(:article, title: "画像のある記事", url: source_url("image"), image_url: "/icon.png", published_at: now - 1.hour)
    plain = create(:article, title: "画像の無い記事", url: source_url("plain"), published_at: now - 2.hours)
    sign_in

    read_from_saved(article)
    card = find("##{ActionView::RecordIdentifier.dom_id(article, :reader)}")
    expect(card).to have_css("figure:first-child img[src='/icon.png'][referrerpolicy='no-referrer']", visible: :all)
    expect(no_horizontal_scroll?).to be(true), "カードが横にはみ出している"
    screenshot!

    read_from_saved(plain)
    expect(page).to have_css("h1", text: "画像の無い記事")
    expect(page).to have_no_css("figure")
  end

  it "戻りの合図を拾えなかったときは、開いた後に出る「読み終えた」で判定する" do
    article = create(:article, title: "合図の無い記事", url: source_url("silent"), summary: "・一")
    sign_in

    read_from_saved(article)
    expect(page).to have_no_button("読み終えた")

    # 合図を拾えなかった体にする（iPhone のシートで focus も visibilitychange も来ない場合）。
    # 別窓を開かせなければ Reader は隠れも focus を失いもしないので、リンクの遷移だけ止める（sheet#open は走る）
    page.execute_script(<<~JS)
      document.addEventListener("click", (event) => { if (event.target.closest("a[target=_blank]")) event.preventDefault() }, true)
    JS
    since = article.reload.reading.opened_at
    click_on "記事を開く"
    wait_for_start(article.reading, since: since)
    make_dwell(article.reading, threshold + 5)

    expect(page).to have_button("読み終えた")
    expect(article.reading.reload.returned_at).to be_nil
    screenshot!("opened")

    click_on "読み終えた"

    expect(page).to have_css("section[aria-label='判定']", text: "カードを手に入れた！")
    expect(page).to have_text("全部読んだ")
    expect(article.reading.reload).to be_completed
  end

  # iPhone のホーム画面アプリで実機の合図を並べると、「記事を開く」を押した瞬間に blur → focus が続けて来て、
  # その後に hidden、シートを閉じると visible → focus だった。押した瞬間の focus を戻りと取り違えない
  it "押した瞬間の blur と focus では判定せず、隠れた後に見える状態へ戻ったときに判定する" do
    article = create(:article, title: "シートの記事", url: source_url("sheet"), summary: "・一")
    sign_in

    read_from_saved(article)
    page.execute_script(<<~JS)
      document.addEventListener("click", (event) => { if (event.target.closest("a[target=_blank]")) event.preventDefault() }, true)
      window.__visibility = "visible"
      Object.defineProperty(document, "visibilityState", { configurable: true, get: () => window.__visibility })
      window.__setVisibility = (state) => { window.__visibility = state; document.dispatchEvent(new Event("visibilitychange")) }
    JS
    since = article.reload.reading.opened_at
    click_on "記事を開く"
    page.execute_script('window.dispatchEvent(new Event("blur")); window.dispatchEvent(new Event("focus"))')
    wait_for_start(article.reading, since: since)

    expect(page).to have_button("読み終えた")
    expect(page).to have_no_css("section[aria-label='判定']")
    expect(article.reading.reload.returned_at).to be_nil

    page.execute_script('window.dispatchEvent(new Event("blur")); window.__setVisibility("hidden")')
    make_dwell(article.reading, threshold + 5)
    page.execute_script('window.__setVisibility("visible"); window.dispatchEvent(new Event("focus"))')

    expect(page).to have_css("section[aria-label='判定']", text: "カードを手に入れた！")
    expect(article.reading.reload).to be_completed
  end

  describe "要約は「読む」を押してから作る" do
    let(:summarizer) { instance_double(Claude::Summarizer, call: "・できた要約\n・二\n・三") }

    before { allow(Claude::Summarizer).to receive(:new).and_return(summarizer) }

    def stream_connected
      find("turbo-cable-stream-source[connected]", visible: :all)
    end

    it "出来るまでは「作成中」、Job が書き終えるとその欄だけ差し替わる" do
      article = create(:article, :awaiting_summary, title: "要約待ちの記事", url: source_url("pending"))
      sign_in

      read_from_saved(article)
      expect(page).to have_text("要約を作成中")
      expect(page).to have_link("記事を開く", href: article.url)
      stream_connected
      screenshot!("pending")

      Claude::SummarizeArticleJob.perform_now(article)

      expect(page).to have_css("section[aria-label='要約']", text: "・できた要約")
      expect(page).to have_no_text("要約を作成中")
      expect(page).to have_no_css("turbo-cable-stream-source", visible: :all) # 出来上がったら購読を残さない（継ぎ足すたびに溜まる）
      screenshot!("ready")
    end

    it "つながり直したとき作成中なら欄を取り直す（つながっていない間に書き終えた分）" do
      article = create(:article, :awaiting_summary, :opened, title: "取り直す記事", url: source_url("refresh"))
      sign_in

      visit read_article_path(article)
      stream_connected
      article.update!(summary: "・切れている間の要約") # broadcast しない
      page.execute_script(<<~JS)
        const source = document.querySelector("[data-controller='summary-refresh'] turbo-cable-stream-source")
        source.removeAttribute("connected")
        source.setAttribute("connected", "")
      JS

      expect(page).to have_css("section[aria-label='要約']", text: "・切れている間の要約")
      expect(page).to have_no_css("turbo-cable-stream-source", visible: :all) # 取り直しで出来上がったら購読を外す
    end

    it "失敗したら「要約できませんでした」。記事はそのまま開ける" do
      allow(summarizer).to receive(:call).and_raise(Claude::Summarizer::EmptyContent, "本文が空")
      article = create(:article, :awaiting_summary, :opened, title: "要約できない記事", url: source_url("failed"))
      sign_in

      visit read_article_path(article)
      stream_connected
      Claude::SummarizeArticleJob.perform_now(article)

      expect(page).to have_css("section[aria-label='要約']", text: "要約できませんでした")
      expect(page).to have_link("記事を開く", href: article.url)
      expect(no_horizontal_scroll?).to be(true), "カードが横にはみ出している"
      screenshot!("failed")
    end
  end
end
