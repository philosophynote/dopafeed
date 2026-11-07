# 読む → Roulette → リーダーと、jackpot → Jackpot → 受け取って読む → リーダーを 390×844 で通す
RSpec.describe "Roulette", type: :system do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:base) { settings.dig(:xp, :base) }
  let(:common) { Dopamine.tier_names.first }
  let(:jackpot) { Dopamine.jackpot_tier }

  def create_article(title = "読む記事")
    create(:article, title: title, url: "#{Capybara.current_session.server.base_url}/up?#{title}")
  end

  it "読むと止まった出目の帯つきでリーダーが開き、モーダルは残らない" do
    allow(XpRoulette).to receive(:draw).and_return(common)
    article = create_article
    sign_in

    click_on "読む"
    expect(page).to have_current_path(read_article_path(article))
    expect(page).to have_text("出目 通常 ×1 ・ 完読で +#{base} XP")
    expect(page).to have_no_css("[data-controller='roulette']")
    expect(article.reload.reading.returned_at).to be_nil
  end

  it "回っている間は一覧の上にモーダルが重なり、背景のカードは残る（絵のためにこの例だけ長く回す）" do
    long = settings.deep_dup
    long[:xp][:roulette_duration_ms] = 10_000
    allow(Dopamine).to receive(:settings).and_return(long)
    allow(XpRoulette).to receive(:draw).and_return(common)
    article = create_article("背景に残るカード")
    sign_in

    click_on "読む"

    expect(page).to have_css("[role='dialog'][aria-label='ルーレット']")
    expect(page).to have_text("「読む」を押した 10.0 秒間")
    expect(page).to have_css("article", text: "背景に残るカード")
    expect(page).to have_current_path(root_path)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    expect(article.reload.reading.tier).to eq(common)
  end

  it "jackpot なら全画面に進み、受け取って読むでリーダーが開き、記事を開いて戻ると jackpot の倍率で XP が付く" do
    allow(XpRoulette).to receive(:draw).and_return(jackpot[:name])
    article = create_article
    sign_in

    click_on "読む"
    expect(page).to have_text("JACKPOT")
    expect(page).to have_current_path(jackpot_reading_path(article.reload.reading))
    expect(page).to have_text("+#{base * jackpot[:multiplier]}")
    expect(page).to have_no_button("閉じる")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "紙吹雪が横スクロールを生んでいる"
    screenshot!("jackpot")

    # 戻るで Main に帰っても、モーダルは蘇らず、読了も勝手に送られない。結果は保持され、再び読めば同じ Jackpot
    page.go_back
    expect(page).to have_current_path(root_path)
    expect(page).to have_css("article", text: "読む記事")
    expect(page).to have_no_css("[data-controller='roulette']")
    expect(page).to have_no_text("読了！")
    expect(article.reading.reload.returned_at).to be_nil
    click_on "読む"
    expect(page).to have_text("JACKPOT")
    expect(page).to have_current_path(jackpot_reading_path(article.reading))

    click_on "受け取って読む"
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
    expect(page).to have_css("section[aria-label='判定']", text: "読了！ +#{base * jackpot[:multiplier]} XP")
    expect(article.reading.reload).to be_completed
  end
end
