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

  def wait_for_sfx(count, within: Capybara.default_max_wait_time)
    Timeout.timeout(within) { sleep 0.05 until sfx_log.size >= count }
    sfx_log
  rescue Timeout::Error
    sfx_log
  end

  def sound_switch
    find("button[role='switch']", text: "効果音")
  end

  it "設定画面の「効果音」は初めはオンで、切り替えると再読込しても残り、オンに戻したときだけ試しに 1 回鳴る" do
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
    expect(sfx_log).to eq([ "tap" ])
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

  it "再読込してから同じ行を広げ直しても、抽選し直していない出目の音は鳴り直さない" do
    allow(RarityDraw).to receive(:draw).and_return(rare)
    create(:article, title: "レアの記事")
    sign_in

    expand("レアの記事")
    expect(wait_for_sfx(2)).to eq(%w[tap rare])

    page.refresh
    expand("レアの記事")
    sleep 0.3
    expect(sfx_log).to eq(%w[tap rare tap])
  end

  it "応答を待つ間に別の行を押して、畳まれたまま届いた行の出目の音は鳴らない" do
    allow(RarityDraw).to receive(:draw).and_return(rare)
    create(:article, title: "先に押す記事", published_at: 1.hour.ago)
    create(:article, title: "後に押す記事", published_at: 2.hours.ago)
    sign_in
    # 先の行の応答だけを遅らせる（後の行は送信の列で先の応答を待つので、先の行の欄が届く前に後の行を押した状態になる）
    page.execute_script(<<~JS)
      const original = window.fetch
      window.fetch = (...args) => {
        const body = args[1]?.body
        const slow = String(args[0]).includes("/reading") && !window.__slowed
        if (slow) window.__slowed = true
        return slow ? new Promise((resolve) => setTimeout(() => resolve(original(...args)), 500)) : original(...args)
      }
    JS

    find("article", text: "先に押す記事").find_button("読む").click
    find("article", text: "後に押す記事").find_button("読む").click
    expect(page).to have_link("記事に遷移", count: 1)
    sleep 0.5
    expect(sfx_log).to eq(%w[tap tap rare])
  end

  it "動きを減らす設定では、ルーレットが止まって見えるのと同時に鳴る" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    allow(RarityDraw).to receive(:draw).and_return(rare)
    create(:article, title: "レアの記事").bookmark!
    sign_in
    visit saved_path

    button = find("article", text: "レアの記事").find_button("読む")
    elapsed = page.evaluate_async_script(<<~JS, button.native)
      const [button, done] = arguments
      const start = performance.now()
      button.click()
      const poll = () => (sessionStorage.getItem("sfx-log") || "").includes("rare") ? done(performance.now() - start) : setTimeout(poll, 10)
      poll()
    JS
    expect(elapsed).to be < Dopamine.settings.dig(:cards, :reveal_duration_ms) * 0.7
  end

  it "一覧で未完なら煙、完読なら段に応じた音（今日の 1 枚目は見せ場の音）が鳴り、Turbo の履歴で戻っても再読込しても鳴り直さない" do
    allow(RarityDraw).to receive(:draw).and_return(common)
    create(:article, title: "読む記事", summary: "・要約")
    sign_in

    expand("読む記事")
    read_in_list("読む記事", dwell: 1)
    expect(page).to have_css("section[aria-label='判定']", text: "カードにならなかった")
    expect(wait_for_sfx(2)).to eq(%w[tap puff])

    read_in_list("読む記事", dwell: threshold + 5)
    expect(page).to have_css("section[aria-label='判定']", text: "を手に入れた！")
    expect(wait_for_sfx(3)).to eq(%w[tap puff highlight])

    # visit だとブラウザの遷移になり、Turbo のスナップショットを通らない
    find("a[aria-label='設定']").click
    expect(page).to have_css("button[role='switch']", text: "効果音")
    page.go_back
    expect(page).to have_css("section[aria-label='判定']", text: "を手に入れた！")
    sleep 0.3
    expect(sfx_log).to eq(%w[tap puff highlight])

    page.refresh
    expect(page).to have_css("article", text: "読む記事", count: 0)
    sleep 0.3
    expect(sfx_log).to eq(%w[tap puff highlight])
  end

  it "Main の欄で金のカードを手に入れると、全画面は出ないが欄の中でファンファーレが鳴る" do
    allow(RarityDraw).to receive(:draw).and_return(jackpot)
    create(:article, title: "金の記事", summary: "・要約")
    sign_in

    expand("金の記事")
    expect(wait_for_sfx(2)).to eq(%w[tap gold]) # 帯のリールが止まった瞬間
    read_in_list("金の記事", dwell: threshold + 5)
    expect(page).to have_css("section[aria-label='判定']", text: "金のカードを手に入れた！")
    expect(wait_for_sfx(3)).to eq(%w[tap gold fanfare])
  end

  it "Saved のルーレットはレアで止まった瞬間にだけ鳴り、通常では鳴らない" do
    rare_article = create(:article, title: "レアの記事", published_at: 1.hour.ago)
    common_article = create(:article, title: "通常の記事", published_at: 2.hours.ago)
    sign_in
    allow(RarityDraw).to receive(:draw).and_return(rare)
    read_from_saved(rare_article)
    expect(wait_for_sfx(2)).to eq(%w[tap rare])

    allow(RarityDraw).to receive(:draw).and_return(common)
    read_from_saved(common_article)
    sleep 0.3
    expect(sfx_log).to eq(%w[tap rare tap])
  end

  it "スワイプが閾値を越えた瞬間に 1 回だけ鳴り、同じ指で閾値の手前へ戻して越え直しても鳴り直さない" do
    create(:article, title: "払う記事")
    sign_in
    width = card_width("払う記事")

    # 続けて動かすときの座標は、動いた後のカードの左端が基準（system_swipe.rb）
    drag_card("払う記事", from: [ width - 20, 30 ], to: [ 20, 30 ], steps: 8, release: false)
    drag_card("払う記事", from: [ width - 20, 30 ], to: [ (2 * width) - 70, 30 ], steps: 4, release: false, down: false)
    expect(card_shift("払う記事")).to be > -(width * 0.2)
    drag_card("払う記事", from: [ width - 20, 30 ], to: [ 10, 30 ], steps: 4, release: false, down: false)
    expect(sfx_log).to eq([ "swipe" ])
  end

  it "Saved から金を引くと、出目の和音は鳴らさず Jackpot のファンファーレだけ。完読すると全画面の開封のファンファーレだけが鳴る" do
    allow(RarityDraw).to receive(:draw).and_return(jackpot)
    article = create(:article, title: "金の記事", url: "#{Capybara.current_session.server.base_url}/up?gold", summary: "・要約")
    article.bookmark!
    sign_in
    visit saved_path

    within("article", text: "金の記事") { click_on "読む" }
    expect(page).to have_link("読んで手に入れる")
    expect(wait_for_sfx(2)).to eq(%w[tap fanfare])

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
    expect(wait_for_sfx(3)).to eq(%w[tap fanfare fanfare])
  end

  it "宝箱の音は、ゴールを達成した日に宝箱を初めて開いたときだけ鳴る。2 度目からは鳴らない" do
    (goal_articles - 1).times { create(:reading, :completed, opened_at: Time.current - 1.hour) }
    sign_in
    visit daily_goal_path
    expect(page).to have_text("あと 1 本で宝箱")
    sleep 0.3
    expect(sfx_log).to be_empty

    create(:reading, :completed, opened_at: Time.current - 1.hour)
    create(:daily_goal, :achieved, day: ReadingDay.of)
    visit daily_goal_path
    expect(page).to have_text("読み切った！")
    # ファンファーレは蓋・カード・行の後なので、既定の待ち時間より遅れて鳴る
    expect(wait_for_sfx(2, within: 5)).to eq(%w[chest fanfare])

    page.refresh
    expect(page).to have_text("読み切った！")
    sleep 0.3
    expect(sfx_log).to eq(%w[chest fanfare])
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
