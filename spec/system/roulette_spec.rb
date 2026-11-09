# 読む → Roulette → リーダーと、jackpot → Jackpot → 受け取って読む → リーダーを 390×844 で通す。
# Main の行はモーダルを回さず下に広がる（ADR 0019）ので、ルーレットが残る入口の Saved の行から読む
RSpec.describe "Roulette", type: :system do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:common) { Dopamine.rarity_names.first }
  let(:jackpot) { Dopamine.top_rarity }

  def create_article(title = "読む記事")
    create(:article, :bookmarked, title: title, url: "#{Capybara.current_session.server.base_url}/up?#{title}")
  end

  def sign_in_to_saved
    sign_in
    visit saved_path
  end

  it "読むと止まった出目の帯つきでリーダーが開き、モーダルは残らない" do
    allow(RarityDraw).to receive(:draw).and_return(common)
    article = create_article
    sign_in_to_saved

    click_on "読む"
    expect(page).to have_current_path(read_article_path(article))
    expect(page).to have_text("出目 通常 ・ 完読で通常カード")
    expect(page).to have_no_css("[data-controller='roulette']")
    expect(article.reload.reading.returned_at).to be_nil
  end

  it "回っている間は一覧の上にモーダルが重なり、背景のカードは残る（絵のためにこの例だけ長く回す）" do
    long = settings.deep_dup
    long[:cards][:reveal_duration_ms] = 10_000
    allow(Dopamine).to receive(:settings).and_return(long)
    allow(RarityDraw).to receive(:draw).and_return(common)
    article = create_article("背景に残るカード")
    sign_in_to_saved

    click_on "読む"

    expect(page).to have_css("[role='dialog'][aria-label='ルーレット']")
    expect(page).to have_text("「読む」を押した 10.0 秒間")
    expect(page).to have_css("article", text: "背景に残るカード")
    expect(page).to have_current_path(saved_path)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    expect(article.reload.reading.tier).to eq(common)
  end

  it "jackpot なら全画面の予告に進み、読んで手に入れるでリーダーが開き、記事を開いて戻ると金のカードになる" do
    allow(RarityDraw).to receive(:draw).and_return(jackpot[:name])
    article = create_article
    sign_in_to_saved

    click_on "読む"
    expect(page).to have_text("JACKPOT")
    expect(page).to have_current_path(jackpot_reading_path(article.reload.reading))
    expect(page).to have_text("金のカード")
    expect(page).to have_no_text("XP")
    expect(page).to have_no_button("閉じる")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "紙吹雪が横スクロールを生んでいる"
    screenshot!("jackpot")

    # 戻るで一覧に帰っても、モーダルは蘇らず、読了も勝手に送られない。結果は保持され、再び読めば同じ Jackpot
    page.go_back
    expect(page).to have_current_path(saved_path)
    expect(page).to have_css("article", text: "読む記事")
    expect(page).to have_no_css("[data-controller='roulette']")
    expect(page).to have_no_text("手に入れた")
    expect(article.reading.reload.returned_at).to be_nil
    click_on "読む"
    expect(page).to have_text("JACKPOT")
    expect(page).to have_current_path(jackpot_reading_path(article.reading))

    click_on "読んで手に入れる"
    expect(page).to have_current_path(read_article_path(article))
    opened = article.reading.reload.opened_at

    # 元サイトの代わりに /up を別窓で開き、そこにいる間に滞在を作って戻る（戻った瞬間に判定が走る）
    reader = current_window
    source = window_opened_by { click_on "記事を開く" }
    within_window(source) do
      expect(page).to have_current_path("/up", ignore_query: true)
      Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until article.reading.reload.opened_at > opened }
      article.reading.update_columns(opened_at: Time.current - threshold - 5)
    end
    source.close
    switch_to_window(reader)
    # 金は全画面で開封し、どこを押しても閉じる。閉じた後も区切りの金のカードは残る
    overlay = find("[data-controller='reveal'][role='dialog']")
    expect(overlay).to have_text("金のカードを手に入れた！")
    expect(overlay).to have_css("li.card-reveal[data-tier='#{jackpot[:name]}'] h3", text: "読む記事")
    page.evaluate_async_script("const done = arguments[0]; Promise.all(document.querySelector('[data-controller=reveal] li.card-reveal').getAnimations().map((a) => a.finished)).then(() => done(true))")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    screenshot!("gold")
    expect(page.evaluate_script("document.activeElement.textContent")).to eq("閉じる")
    overlay.find("p", text: "JACKPOT").click # ボタン以外のどこを押しても閉じる
    expect(page).to have_no_css("[data-controller='reveal'][role='dialog']")
    expect(page).to have_css("section[aria-label='判定']", text: "金のカードを手に入れた！")
    expect(page).to have_css("section[aria-label='判定'] li[data-tier='#{jackpot[:name]}'] h3", text: "読む記事")
    expect(article.reading.reload).to be_completed
  end
end
