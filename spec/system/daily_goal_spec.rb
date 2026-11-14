RSpec.describe "DailyGoal", type: :system do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:common) { Dopamine.rarity_names.first }

  before { allow(RarityDraw).to receive(:draw).and_return(common) }

  def no_horizontal_scroll?
    page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
  end

  def small_tap_areas
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("a, button")).map(el => {
        const r = el.getBoundingClientRect();
        return [el.textContent.trim() || el.getAttribute("aria-label"), Math.round(r.width), Math.round(r.height)];
      }).filter(([, w, h]) => w < 44 || h < 44)
    JS
  end

  # fetch が届く前に滞在を書き換えると上書きされるため、opened_at の更新を待つ。
  def wait_for_start(reading, since:)
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until reading.reload.opened_at > since }
  end

  it "goal 本目を読み終えると区切りに「宝箱を開く」が出て、DailyGoal で満足して閉じると Main のドットが全部塗られる" do
    (goal_articles - 1).times { create(:reading, :completed, opened_at: Time.current - 1.hour) }
    article = create(:article, title: "今日の最後の 1 本", url: "#{Capybara.current_session.server.base_url}/up?last", summary: "・一")
    sign_in
    expect(page).to have_text("今日のゴール #{goal_articles - 1} / #{goal_articles}", normalize_ws: true)

    read_from_saved(article)
    page.execute_script(<<~JS)
      document.addEventListener("click", (event) => { if (event.target.closest("a[target=_blank]")) event.preventDefault() }, true)
    JS
    since = article.reload.reading.opened_at
    click_on "記事を開く"
    wait_for_start(article.reading, since: since)
    article.reading.reload.update_columns(opened_at: Time.current - threshold - 5)

    click_on "読み終えた"

    expect(page).to have_css("section[aria-label='判定']", text: "カードを手に入れた！")
    expect(page).to have_text("今日のゴール #{goal_articles} / #{goal_articles} ・ 読み切った！")
    expect(page).to have_link("宝箱を開く")
    screenshot!("divider")

    click_on "宝箱を開く"

    expect(page).to have_current_path(daily_goal_path)
    expect(page).to have_text("今日の #{goal_articles} 本、読み切った！")
    expect(page).to have_css("[data-chest=open]")
    expect(page).to have_text("ストリーク 1 日目 確定")
    expect(page).to have_css("ul.card-deck li.card-reveal[data-tier]", count: goal_articles)
    expect(page).to have_css("ul.card-deck li h3", text: "今日の最後の 1 本")
    expect(page).to have_text("#{goal_articles} 本 ・")
    expect(page).to have_no_button("もう 1 本だけ")
    expect(page).to have_css("[data-finale] .fireworks")
    screenshot!("finale")
    # めくりの途中では回転でカードの幅が縮むため、有限の演出が終わってからタップ領域を測る。
    page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      const finite = document.getAnimations().filter((a) => a.effect?.getComputedTiming().iterations !== Infinity)
      Promise.all(finite.map((a) => a.finished)).then(() => done(true))
    JS
    expect(no_horizontal_scroll?).to be(true), "横スクロールが出ている"
    expect(small_tap_areas).to be_empty, "44px 未満のタップ領域: #{small_tap_areas.inspect}"
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.chest-lid')).transform")).not_to eq("none")
    screenshot!("achieved")

    page.refresh
    expect(page).to have_text("今日の #{goal_articles} 本、読み切った！")
    expect(page).to have_no_css("[data-finale], .fireworks, li.card-reveal")
    expect(page).to have_css("ul.card-deck li[data-tier]", count: goal_articles)
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.chest-lid')).transform")).not_to eq("none"), "2 度目は蓋が開いたまま"
    expect(page.evaluate_script("document.getAnimations().length")).to eq(0)

    click_on "今日はここまで"

    expect(page).to have_current_path(root_path)
    expect(page).to have_css(".goal-dot[data-filled=true]", count: goal_articles)
  end

  describe "宝箱のフィナーレ" do
    before do
      goal_articles.times { create(:reading, :completed, opened_at: Time.current - 1.hour) }
      create(:daily_goal, :achieved, day: ReadingDay.of)
      create(:article, title: "まだ読んでいない記事")
    end

    def running_animations(except: [])
      page.evaluate_script("document.getAnimations().filter((a) => a.playState === 'running').map((a) => a.animationName)") - except
    end

    it "フィナーレの途中で別の画面へ移って履歴で戻っても、やり直さない" do
      sign_in
      visit daily_goal_path
      expect(page).to have_css("[data-finale] .fireworks")

      click_on "今日はここまで"
      expect(page).to have_current_path(root_path)
      page.go_back

      expect(page).to have_css("[data-finale].is-settled")
      expect(page).to have_no_css("li.card-reveal")
      expect(page).to have_no_css(".fireworks")
      expect(running_animations).to be_empty
    end

    it "動きを減らす設定なら、蓋もカードも動かさずに開いた形で出し、花火も出さない" do
      sign_in
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
      visit daily_goal_path

      expect(page).to have_css("[data-finale]")
      expect(page).to have_no_css(".fireworks")
      expect(page).to have_css("section[aria-label='宝箱の中身'] .finale-drop", count: 3)
      expect(running_animations(except: %w[chest-open])).to be_empty
    ensure
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    end
  end

  it "達成前に Main のゴール表示をタップすると、閉じた宝箱と「あと N 本」が出て、「読みに戻る」で Main へ" do
    2.times { create(:reading, :completed, opened_at: Time.current - 1.hour) }
    create(:article, title: "まだ読んでいない記事")
    sign_in

    click_on "今日のゴール 2 / #{goal_articles}"

    expect(page).to have_current_path(daily_goal_path)
    expect(page).to have_css("[data-chest=closed]")
    expect(page).to have_text("あと #{goal_articles - 2} 本で宝箱")
    expect(page).to have_no_button("もう 1 本だけ")
    expect(no_horizontal_scroll?).to be(true), "横スクロールが出ている"
    expect(small_tap_areas).to be_empty, "44px 未満のタップ領域: #{small_tap_areas.inspect}"
    screenshot!("pending")

    click_on "読みに戻る"
    expect(page).to have_current_path(root_path)
  end
end
