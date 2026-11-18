RSpec.describe "Saved から読む", type: :system do
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

  it "未読の行を押すと、モーダルを挟まず Reader が開き、帯のリールが出目で止まる" do
    allow(RarityDraw).to receive(:draw).and_return(common)
    article = create_article
    sign_in_to_saved

    click_on "読む"
    expect(page).to have_current_path(read_article_path(article))
    expect(page).to have_no_css("[role='dialog']")
    band = find("[data-tier='#{common}']", text: "出目 通常 ・ 完読で通常カード")
    expect(band).to have_css(".reel-inner")
    page.evaluate_async_script("const done = arguments[0]; Promise.all(document.querySelector('.reel-inner').getAnimations({ subtree: true }).map((a) => a.finished)).then(() => done(true))")
    expect(article.reload.reading.returned_at).to be_nil
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    screenshot!("reader")

    page.refresh
    expect(find("[data-tier='#{common}']", text: "出目 通常")).to have_no_css(".reel-inner")
  end

  it "頂点の出目でも全画面の予告は出ず Reader が開き、記事を開いて戻ると金のカードを全画面で開封する" do
    allow(RarityDraw).to receive(:draw).and_return(jackpot[:name])
    article = create_article
    sign_in_to_saved

    click_on "読む"
    expect(page).to have_current_path(read_article_path(article))
    expect(page).to have_css("[data-tier='#{jackpot[:name]}']", text: "出目 金 ・ 完読で金のカード")
    expect(page).to have_no_css("[role='dialog']")

    page.go_back
    expect(page).to have_current_path(saved_path)
    expect(page).to have_css("article", text: "読む記事")
    expect(page).to have_no_text("手に入れた")
    expect(article.reading.reload.returned_at).to be_nil
    click_on "読む"
    expect(page).to have_current_path(read_article_path(article))
    opened = article.reading.reload.opened_at

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
