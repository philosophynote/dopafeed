# 5 本目（daily_goal.articles）を読み終えて宝箱を開き、満足して閉じる、を 390×844 で通す（docs/screens/daily_goal.md）。
# 戻りの合図は使わず、「記事を開く」の後の「読み終えた」で判定する（reader_spec が合図の経路を見ている）。
# 滞在は travel_to ではなく opened_at を書き換えて作る（ブラウザの時計とずれないように）
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

  # 「記事を開く」の POST /readings/:id/start は fetch で送るので、届いて opened_at が書き換わるまで待つ
  def wait_for_start(reading, since:)
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until reading.reload.opened_at > since }
  end

  it "goal 本目を読み終えると区切りに「宝箱を開く」が出て、DailyGoal で満足して閉じると Main のドットが全部塗られる" do
    (goal_articles - 1).times { create(:reading, :completed, opened_at: Time.current - 1.hour) }
    article = create(:article, title: "今日の最後の 1 本", url: "#{Capybara.current_session.server.base_url}/up?last", summary: "・一")
    sign_in
    expect(page).to have_text("今日のゴール #{goal_articles - 1} / #{goal_articles}", normalize_ws: true)

    read_from_saved(article)
    # 別窓は開かせず、リンクの遷移だけ止める（sheet#open は走り、「読み終えた」が出る）
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
    expect(page).to have_text("#{goal_articles} 本 ・")
    expect(page).to have_no_button("もう 1 本だけ") # 未読が尽きた
    expect(no_horizontal_scroll?).to be(true), "横スクロールが出ている"
    expect(small_tap_areas).to be_empty, "44px 未満のタップ領域: #{small_tap_areas.inspect}"
    # 蓋が持ち上がり切ってから撮る（開いた宝箱は描いた直後に動き出す）
    page.evaluate_async_script("const done = arguments[0]; Promise.all(document.querySelector('.chest-lid').getAnimations().map((a) => a.finished)).then(() => done(true))")
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.chest-lid')).transform")).not_to eq("none")
    screenshot!("achieved")

    click_on "今日はここまで"

    expect(page).to have_current_path(root_path)
    expect(page).to have_css(".goal-dot[data-filled=true]", count: goal_articles)
  end

  it "達成前に Main のゴール表示をタップすると、閉じた宝箱と「あと N 本」が出て、「読みに戻る」で Main へ" do
    2.times { create(:reading, :completed, opened_at: Time.current - 1.hour) }
    create(:article, title: "まだ読んでいない記事")
    sign_in

    click_on "今日のゴール 2 / #{goal_articles}"

    expect(page).to have_current_path(daily_goal_path)
    expect(page).to have_css("[data-chest=closed]")
    expect(page).to have_text("あと #{goal_articles - 2} 本で宝箱")
    expect(page).to have_no_button("もう 1 本だけ") # 読み足すなら Main の「読む」
    expect(no_horizontal_scroll?).to be(true), "横スクロールが出ている"
    expect(small_tap_areas).to be_empty, "44px 未満のタップ領域: #{small_tap_areas.inspect}"
    screenshot!("pending")

    click_on "読みに戻る"
    expect(page).to have_current_path(root_path)
  end
end
