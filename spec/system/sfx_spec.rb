RSpec.describe "効果音", type: :system do
  let(:threshold) { Dopamine.settings.dig(:read, :complete_after_seconds) }
  let(:goal_articles) { Dopamine.settings.dig(:daily_goal, :articles) }
  let(:common) { Dopamine.rarity_names.first }
  let(:rare) { Dopamine.rarity_names.second }
  let(:jackpot) { Dopamine.top_rarity[:name] }

  # test 環境の sfx は音を出さず、鳴らした音の名前をタブの sessionStorage に記録する（画面を移っても残る）
  def sfx_log
    page.evaluate_script('JSON.parse(sessionStorage.getItem("sfx-log") || "[]")')
  end

  def wait_for_sfx(count)
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until sfx_log.size >= count }
    sfx_log
  rescue Timeout::Error
    sfx_log
  end

  def sound_switch
    find("button[role='switch']", text: "効果音")
  end

  def expand(title)
    find("article", text: title).find_button("読む").click
    expect(page).to have_link("記事に遷移")
  end

  # 別窓を開かせず、開いた時刻が届くのを待ってから滞在を作る
  def read_in_list(title, dwell:)
    page.execute_script(<<~JS)
      document.addEventListener("click", (event) => { if (event.target.closest("a[target=_blank]")) event.preventDefault() }, true)
    JS
    reading = Article.find_by!(title: title).reading
    since = reading.reload.opened_at
    find("li", text: title).find_link("記事に遷移").click
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until reading.reload.opened_at > since }
    reading.update_columns(opened_at: Time.current - dwell)
    click_on "読み終えた"
  end

  it "設定画面の「効果音」は初めはオンで、切り替えると再読込しても残る" do
    sign_in
    visit learning_path

    expect(sound_switch["aria-checked"]).to eq("true")
    sound_switch.click
    expect(sound_switch["aria-checked"]).to eq("false")

    visit learning_path
    expect(sound_switch["aria-checked"]).to eq("false")
    expect(sound_switch.evaluate_script("this.getBoundingClientRect().height")).to be >= 44
    screenshot!("off")

    sound_switch.click
    expect(sound_switch["aria-checked"]).to eq("true")
    expect(sfx_log).to eq([ "tap" ]) # オンに戻したときだけ試しに鳴らす
    screenshot!("on")
  end

  it "Main で行を広げると、タップの音とレアの出目の音が 1 回ずつ鳴る。通常の出目では出目の音は鳴らない" do
    create(:article, title: "レアの記事", published_at: 1.hour.ago)
    create(:article, title: "通常の記事", published_at: 2.hours.ago)
    sign_in

    allow(RarityDraw).to receive(:draw).and_return(rare)
    expand("レアの記事")
    expect(wait_for_sfx(2)).to eq(%w[tap rare])

    allow(RarityDraw).to receive(:draw).and_return(common)
    expand("通常の記事")
    expect(wait_for_sfx(3)).to eq(%w[tap rare tap])
  end

  it "一覧で未完なら煙、完読ならめくりの音が鳴り、履歴で戻っても鳴り直さない" do
    allow(RarityDraw).to receive(:draw).and_return(common)
    create(:article, title: "読む記事", summary: "・要約")
    sign_in

    expand("読む記事")
    read_in_list("読む記事", dwell: 1)
    expect(page).to have_css("section[aria-label='判定']", text: "カードにならなかった")
    expect(wait_for_sfx(2)).to eq(%w[tap puff])

    read_in_list("読む記事", dwell: threshold + 5)
    expect(page).to have_css("section[aria-label='判定']", text: "を手に入れた！")
    expect(wait_for_sfx(3)).to eq(%w[tap puff card])

    visit learning_path
    page.go_back
    expect(page).to have_css("section[aria-label='判定']", text: "を手に入れた！")
    sleep 0.3
    expect(sfx_log).to eq(%w[tap puff card])
  end

  it "スワイプが閾値を越えた瞬間に 1 回だけ鳴る" do
    create(:article, title: "払う記事")
    sign_in
    width = card_width("払う記事")

    drag_card("払う記事", from: [ width - 20, 30 ], to: [ 20, 30 ], steps: 8, release: false)
    drag_card("払う記事", from: [ 20, 30 ], to: [ 10, 30 ], steps: 2, release: false, down: false)
    expect(sfx_log).to eq([ "swipe" ])
  end

  it "Saved から金を引くと、タップの音、出目が止まって金の音、Jackpot でファンファーレ。完読すると全画面の開封のファンファーレだけが鳴る" do
    allow(RarityDraw).to receive(:draw).and_return(jackpot)
    article = create(:article, title: "金の記事", url: "#{Capybara.current_session.server.base_url}/up?gold", summary: "・要約")
    article.bookmark!
    sign_in
    visit saved_path

    within("article", text: "金の記事") { click_on "読む" }
    expect(page).to have_link("読んで手に入れる")
    expect(wait_for_sfx(3)).to eq(%w[tap gold fanfare])

    click_on "読んで手に入れる"
    page.execute_script(<<~JS)
      document.addEventListener("click", (event) => { if (event.target.closest("a[target=_blank]")) event.preventDefault() }, true)
    JS
    reading = article.reload.reading
    since = reading.opened_at
    click_on "記事を開く"
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until reading.reload.opened_at > since }
    reading.update_columns(opened_at: Time.current - threshold - 5)
    click_on "読み終えた"

    expect(page).to have_css("[role='dialog'][aria-label='金のカードの開封']")
    expect(wait_for_sfx(4)).to eq(%w[tap gold fanfare fanfare])
  end

  it "ゴールを達成した日に宝箱を開くと宝箱の音が鳴る" do
    goal_articles.times { create(:reading, :completed, opened_at: Time.current - 1.hour) }
    sign_in
    visit daily_goal_path

    expect(page).to have_text("読み切った！")
    expect(wait_for_sfx(1)).to eq([ "chest" ])
  end

  it "効果音を切ると、どこでも鳴らない" do
    allow(RarityDraw).to receive(:draw).and_return(rare)
    create(:article, title: "レアの記事")
    sign_in
    visit learning_path
    sound_switch.click
    visit root_path

    expand("レアの記事")
    sleep 0.3
    expect(sfx_log).to be_empty
  end
end
