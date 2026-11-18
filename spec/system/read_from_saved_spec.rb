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

  def complete_in_reader(article)
    page.execute_script(<<~JS)
      document.addEventListener("click", (event) => { if (event.target.closest("a[target=_blank]")) event.preventDefault() }, true)
    JS
    reading = article.reload.reading
    since = reading.opened_at
    click_on "記事を開く"
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until reading.reload.opened_at > since }
    reading.update_columns(opened_at: Time.current - threshold - 5)
    click_on "読み終えた"
    reading
  end

  it "未読の行を押すと、モーダルを挟まず Reader が開き、帯は判定を待つ。判定が届くとリールが段で止まり、再読込では回さない" do
    rare = Dopamine.rarity(Dopamine.rarity_names.second)
    judgment_pending
    article = create_article
    sign_in_to_saved

    click_on "読む"
    expect(page).to have_current_path(read_article_path(article))
    expect(page).to have_no_css("[role='dialog']")
    expect(page).to have_css("[data-state='pending']", text: /判定中.*中身で枠が決まる/)
    expect(article.reload.reading.returned_at).to be_nil
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    screenshot!("judging")

    judgment_arrives(article, rare[:name])
    band = find("[data-tier='#{rare[:name]}']", text: "#{rare[:min_total]} 点 レア ・ 完読でレアカード")
    expect(band).to have_css(".reel-inner")
    page.evaluate_async_script("const done = arguments[0]; Promise.all(document.querySelector('.reel-inner').getAnimations({ subtree: true }).map((a) => a.finished)).then(() => done(true))")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    screenshot!("reader")

    page.refresh
    expect(find("[data-tier='#{rare[:name]}']", text: "#{rare[:min_total]} 点 レア")).to have_no_css(".reel-inner")
  end

  it "判定中のまま完読すると、破線の枠のカードで区切り、判定が届くと見出しとカードの枠が届いた段に替わり、6 軸のレーダーが出る。頂点でも全画面は出ない" do
    judgment_pending
    article = create_article
    sign_in_to_saved
    click_on "読む"
    complete_in_reader(article)

    divider = find("section[aria-label='判定']")
    expect(divider).to have_text("読了 ・ 判定中")
    expect(divider).to have_text("カードを手に入れた！")
    expect(divider).to have_css("li.border-dashed[data-tier=''] [data-rarity-label]", text: "判定中")
    page.evaluate_async_script("const done = arguments[0]; Promise.all(document.querySelector('section[aria-label=判定] li.card-reveal').getAnimations().map((a) => a.finished)).then(() => done(true))")
    screenshot!("judging_divider")

    judgment_arrives(article, jackpot[:name])
    expect(divider).to have_text("読了 ・ #{jackpot[:min_total]} 点")
    expect(divider).to have_text("SS レアカードを手に入れた！")
    expect(divider).to have_css("li.border-amber-400[data-tier='#{jackpot[:name]}'] [data-rarity-label]", text: "SS レア")
    expect(divider).to have_css("svg[role='img'] polygon[data-radar-area]")
    expect(divider).to have_css("figcaption", text: "合計 #{jackpot[:min_total]} 点")
    expect(page).to have_no_css("[role='dialog']")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    page.execute_script("document.querySelector('section[aria-label=判定] figure').scrollIntoView({ block: 'center' })")
    screenshot!("radar_divider")
  end

  it "判定中のまま完読した後、接続が切れている間に決まった枠は、接続が戻ると帯と一緒に区切りの見出しとカードとレーダーにも届く" do
    rare = Dopamine.rarity(Dopamine.rarity_names.second)
    judgment_pending
    article = create_article
    sign_in_to_saved
    click_on "読む"
    reading = complete_in_reader(article)
    divider = find("section[aria-label='判定']")
    expect(divider).to have_text("読了 ・ 判定中")
    find("#rarity_reading_#{reading.id} turbo-cable-stream-source[connected]", visible: :all)

    create(:article_judgment, article: article, **scores_for(rare[:name]))
    Reading.settle_tier!(article) # broadcast しない
    page.execute_script(<<~JS)
      const source = document.querySelector("#rarity_reading_#{reading.id} turbo-cable-stream-source")
      source.removeAttribute("connected")
      source.setAttribute("connected", "")
    JS

    expect(page).to have_css("#rarity_reading_#{reading.id} [data-tier='#{rare[:name]}']")
    expect(divider).to have_text("読了 ・ #{rare[:min_total]} 点")
    expect(divider).to have_text("レアカードを手に入れた！")
    expect(divider).to have_css("li[data-tier='#{rare[:name]}'] [data-rarity-label]", text: "レア")
    expect(divider).to have_css("figcaption", text: "合計 #{rare[:min_total]} 点")
    expect(page).to have_no_css("turbo-frame turbo-stream", visible: :all)
  end

  it "頂点の段の記事でも全画面の予告は出ず Reader が開き、記事を開いて戻ると SS レアカードを全画面で開封する" do
    allow(Reading).to receive(:tier_at_open).and_return(jackpot[:name])
    article = create_article
    sign_in_to_saved

    click_on "読む"
    expect(page).to have_current_path(read_article_path(article))
    expect(page).to have_css("[data-tier='#{jackpot[:name]}']", text: "SS レア ・ 完読でSS レアカード")
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
    # 金は全画面で開封し、どこを押しても閉じる。閉じた後も区切りのSS レアカードは残る
    overlay = find("[data-controller='reveal'][role='dialog']")
    expect(overlay).to have_text("SS レアカードを手に入れた！")
    expect(overlay).to have_css("li.card-reveal[data-tier='#{jackpot[:name]}'] h3", text: "読む記事")
    page.evaluate_async_script("const done = arguments[0]; Promise.all(document.querySelector('[data-controller=reveal] li.card-reveal').getAnimations().map((a) => a.finished)).then(() => done(true))")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    screenshot!("gold")
    expect(page.evaluate_script("document.activeElement.textContent")).to eq("閉じる")
    overlay.find("p", text: "JACKPOT").click # ボタン以外のどこを押しても閉じる
    expect(page).to have_no_css("[data-controller='reveal'][role='dialog']")
    expect(page).to have_css("section[aria-label='判定']", text: "SS レアカードを手に入れた！")
    expect(page).to have_css("section[aria-label='判定'] li[data-tier='#{jackpot[:name]}'] h3", text: "読む記事")
    expect(article.reading.reload).to be_completed
  end
end
