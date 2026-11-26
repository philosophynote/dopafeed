RSpec.describe "FlowMode", type: :system do
  let(:now) { Time.current }

  def create_articles(count)
    (1..count).map { |n| create(:article, title: "記事 #{n}", published_at: now - n.hours) }
  end

  def enter_flow_mode
    choose "無限スクロール", allow_label_click: true
    expect(page).to have_css("[data-flow-mode]")
  end

  # 行の下端を画面の上端より上へ送る
  def scroll_past(title)
    page.execute_script(<<~JS, title)
      const row = [...document.querySelectorAll(".swipe-list > li")].find((li) => li.textContent.includes(arguments[0]))
      window.scrollTo(0, window.scrollY + row.getBoundingClientRect().bottom + 1)
    JS
  end

  def flowed_titles = all("li[data-flowed] article h2", visible: :all).map { |h2| h2.text(:all) }
  def dismissed_titles = Article.where.not(dismissed_at: nil).order(published_at: :desc).pluck(:title)

  it "流すモードで画面の上へ流れ切った行は、止まったときにまとめて削除され、薄く残る。トーストの「元に戻す」で戻った行は流し直さない" do
    create_articles(8)
    sign_in
    switch = find("fieldset.process-mode-switch")
    expect(switch.all("label").map { |label| label.text.lines.first.strip }).to eq(%w[読む 処理 流す])
    expect(switch).to have_field("無限スクロール", visible: :all)
    expect(switch.evaluate_script("this.getBoundingClientRect().right")).to be <= SystemScreen::SCREEN_SIZE[0]
    expect(page.evaluate_script("document.documentElement.scrollWidth")).to eq(SystemScreen::SCREEN_SIZE[0])
    enter_flow_mode
    screenshot!("header")

    scroll_past("記事 3")
    expect(page).to have_css("#toast [data-controller='toast']", text: "3 件を流しました")
    expect(flowed_titles).to eq([ "記事 1", "記事 2", "記事 3" ])
    expect(dismissed_titles).to eq([ "記事 1", "記事 2", "記事 3" ])
    expect(page).to have_css("[data-unread-badge]", text: "5")
    expect(find("button", text: /片付ける/)).to have_text("残り 5 件を片付ける")
    expect(Reading.count).to eq(0)
    page.execute_script("window.scrollTo(0, 0)")
    screenshot!("flowed")

    find("#toast").click_on("元に戻す")
    expect(page).to have_no_css("li[data-flowed]", visible: :all)
    expect(dismissed_titles).to be_empty
    expect(page).to have_css("[data-unread-badge]", text: "8")

    scroll_past("記事 4")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を流しました")
    expect(dismissed_titles).to eq([ "記事 4" ])
  end

  it "薄い行をタップすると、その 1 本だけが戻り、トーストは残る" do
    create_articles(8)
    sign_in
    enter_flow_mode
    scroll_past("記事 2")
    expect(page).to have_css("#toast [data-controller='toast']", text: "2 件を流しました")

    page.execute_script("window.scrollTo(0, 0)")
    find("li[data-flowed]", text: "記事 1").click_on("タップで戻す")
    expect(page).to have_no_css("li[data-flowed]", text: "記事 1")
    expect(flowed_titles).to eq([ "記事 2" ])
    expect(dismissed_titles).to eq([ "記事 2" ])
    expect(page).to have_css("#toast [data-controller='toast']", text: "2 件を流しました")
    expect(page).to have_css("[data-unread-badge]", text: "7")
  end

  it "読むモードでは流れても消えず、流すモードに入る前に上へ流れていた行も消さない。開き直すと読むモードで、流した行は出ない" do
    create_articles(20)
    sign_in
    scroll_past("記事 2")
    # choose はラジオを画面に入れようとして一番上まで戻すので、スクロールを保ったまま切り替える
    page.execute_script("document.querySelector('input[name=mode][value=flow]').click()")
    expect(page).to have_css("[data-flow-mode]")

    scroll_past("記事 3")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を流しました")
    expect(dismissed_titles).to eq([ "記事 3" ])

    visit root_path
    expect(page).to have_checked_field("読む", visible: :all)
    expect(page).to have_no_css("[data-flow-mode]")
    expect(page).to have_css("article h2", text: "記事 2")
    expect(page).to have_no_css("article h2", text: "記事 3")
  end

  it "広げた行は流れても消さない" do
    create_articles(8)
    sign_in
    enter_flow_mode
    expand("記事 1")

    scroll_past("記事 2")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を流しました")
    expect(dismissed_titles).to eq([ "記事 2" ])
  end

  it "最後の行まで流し切ると「全部流した」と出る" do
    create_articles(3)
    sign_in
    enter_flow_mode

    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
    expect(page).to have_css("#toast [data-controller='toast']", text: "3 件を流しました")
    expect(page).to have_text("全部流した。")
    expect(page.evaluate_script("document.querySelector('.flow-done').getBoundingClientRect().top")).to be_between(0, SystemScreen::SCREEN_SIZE[1])
    expect(dismissed_titles).to eq([ "記事 1", "記事 2", "記事 3" ])
    screenshot!("all_flowed")
  end
end
