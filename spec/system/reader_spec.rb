# 読む → Roulette → Reader のカード → 「記事を開く」で元サイトを別窓に開く → 戻ると判定と次の記事が継ぎ足される、を 390×844 で通す。
# iPhone のホーム画面アプリではシートで開くが、headless Chrome では別窓（タブ）になる。戻りの合図はどちらも focus か visibilitychange。
# 滞在は travel_to ではなく opened_at を書き換えて作る（ブラウザの時計とずれないように）
RSpec.describe "Reader", type: :system do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:base) { settings.dig(:xp, :base) }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:common) { Dopamine.tier_names.first }
  let(:now) { Time.current }
  # 元サイトの代わり。外へは出ないので、このアプリの /up（ヘルスチェック）を開く。url は記事ごとに一意なので問い合わせ文字列で分ける
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

    within("article", text: "最初の記事") { click_on "読む" }
    expect(page).to have_current_path(read_article_path(first))
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
    expect(page).to have_no_button("読み終えた") # 継ぎ足された次のカードも、開くまでは隠す
    screenshot!("divider")

    # 次の記事はすぐ戻ると未完。未読が尽きたら「全部読んだ」
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

  it "戻りの合図を拾えなかったときは、開いた後に出る「読み終えた」で判定する" do
    article = create(:article, title: "合図の無い記事", url: source_url("silent"), summary: "・一")
    sign_in

    click_on "読む"
    expect(page).to have_current_path(read_article_path(article))
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
end
