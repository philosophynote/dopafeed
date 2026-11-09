# iPhone のシートは headless Chrome では別タブになる。滞在はブラウザの時計とずれないよう opened_at で作る。
RSpec.describe "Reader", type: :system do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:base) { settings.dig(:xp, :base) }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:common) { Dopamine.tier_names.first }
  let(:now) { Time.current }
  def source_url(name)
    "#{Capybara.current_session.server.base_url}/up?#{name}"
  end

  before { allow(XpRoulette).to receive(:draw).and_return(common) }

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

    expect(page).to have_css("section[aria-label='判定']", text: "読了！ +#{base} XP")
    expect(page).to have_text("今日のゴール 1 / #{goal_articles}")
    expect(page).to have_css("h1", text: "次の記事")
    expect(page).to have_current_path(read_article_path(first))
    expect(first.reload.reading).to be_completed
    expect(page).to have_no_button("読み終えた")
    screenshot!("divider")

    open_source_and_return(second.reload.reading)
    expect(page).to have_css("section[aria-label='判定']", text: "未完 ・ +0 XP")
    expect(page).to have_text("全部読んだ")
    expect(second.reading.reload).not_to be_completed
    expect(no_horizontal_scroll?).to be(true)

    click_on "閉じる", match: :first
    expect(page).to have_current_path(root_path)
    expect(page).to have_no_text("最初の記事")
    expect(page).to have_text("次の記事")
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

    expect(page).to have_css("section[aria-label='判定']", text: "読了！")
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

    expect(page).to have_css("section[aria-label='判定']", text: "読了！")
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
      expect(page).to have_no_css("turbo-cable-stream-source", visible: :all)
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
      expect(page).to have_no_css("turbo-cable-stream-source", visible: :all)
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
