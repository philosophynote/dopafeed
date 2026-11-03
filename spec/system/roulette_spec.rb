# 読む → Roulette → 記事 → 戻る → ReadDone と、jackpot → Jackpot → 受け取って読む → 戻る → ReadDone を 390×844 で通す。
# 記事の URL は Capybara のサーバー（/up）にして、外に出ずに「記事を開いて戻る」を再現する
RSpec.describe "Roulette", type: :system do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:base) { settings.dig(:xp, :base) }
  let(:common) { Dopamine.tier_names.first }
  let(:jackpot) { Dopamine.jackpot_tier }

  def article_on_this_server(title = "読む記事")
    create(:article, title: title, url: "#{Capybara.current_session.server.base_url}/up")
  end

  it "読むと止まった出目で記事が開き、戻ると ReadDone にモーダルは残らない" do
    allow(XpRoulette).to receive(:draw).and_return(common)
    article = article_on_this_server
    sign_in

    click_on "読む"
    expect(page).to have_current_path("/up")

    travel_to(Time.current + threshold + 5.seconds) do
      page.go_back
      expect(page).to have_text("読了！")
      expect(page).to have_text(/合計\s*\+#{base} XP/)
      expect(page).to have_no_css("[data-controller='roulette']")
    end
    expect(article.reload.reading).to be_completed
  end

  it "回っている間は一覧の上にモーダルが重なり、背景のカードは残る（絵のためにこの例だけ長く回す）" do
    long = settings.deep_dup
    long[:xp][:roulette_duration_ms] = 10_000
    allow(Dopamine).to receive(:settings).and_return(long)
    allow(XpRoulette).to receive(:draw).and_return(common)
    article = article_on_this_server("背景に残るカード")
    sign_in

    click_on "読む"

    expect(page).to have_css("[role='dialog'][aria-label='ルーレット']")
    expect(page).to have_text("「読む」を押した 10.0 秒間")
    expect(page).to have_css("article", text: "背景に残るカード")
    expect(page).to have_current_path(root_path)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    expect(article.reload.reading.tier).to eq(common)
  end

  it "jackpot なら全画面に進み、受け取って読むで記事が開き、戻ると ReadDone の内訳に jackpot の倍率が出る" do
    allow(XpRoulette).to receive(:draw).and_return(jackpot[:name])
    article = article_on_this_server
    sign_in

    click_on "読む"
    expect(page).to have_text("JACKPOT")
    expect(page).to have_current_path(jackpot_reading_path(article.reload.reading))
    expect(page).to have_text("+#{base * jackpot[:multiplier]}")
    expect(page).to have_no_button("閉じる")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "紙吹雪が横スクロールを生んでいる"
    screenshot!("jackpot")

    click_on "受け取って読む"
    expect(page).to have_current_path("/up")

    travel_to(Time.current + threshold + 5.seconds) do
      page.go_back
      expect(page).to have_text("読了！")
      expect(page).to have_text(/完読ボーナス\s*\+#{base * jackpot[:multiplier]} XP/)
    end
    expect(article.reading.reload).to be_completed
  end
end
