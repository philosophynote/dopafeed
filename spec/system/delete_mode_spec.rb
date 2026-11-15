RSpec.describe "Delete mode", type: :system do
  let(:now) { Time.current }
  let(:ratio) { Dopamine.settings.dig(:swipe, :dismiss_threshold_ratio) }

  it "「削除」に切り替えると行ごとに削除ボタンが出て、押すと行が消えてトーストが出て未読数が減る。「読む」に戻すとボタンが消える" do
    create(:article, title: "上の記事", published_at: now - 1.hour)
    create(:article, title: "消す記事", published_at: now - 2.hours)
    create(:article, title: "下の記事", published_at: now - 3.hours)
    sign_in

    mode = find("fieldset", text: "読む")
    expect(mode).to have_checked_field("読む", visible: :all)
    mode.all("label").each { |label| expect(label.evaluate_script("this.getBoundingClientRect().height")).to be >= 44 }
    expect(page).to have_no_button("削除")

    enter_delete_mode
    expect(page).to have_button("削除", count: 3)
    button = find("li", text: "消す記事").find_button("削除")
    rect = button.evaluate_script("this.getBoundingClientRect().toJSON()")
    expect([ rect["width"], rect["height"] ].min).to be >= 44
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    screenshot!("on")

    delete_row("消す記事")

    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました")
    expect(page).to have_no_css("article", text: "消す記事")
    expect(page).to have_css("[data-unread-badge]", text: "2")
    expect(Article.find_by!(title: "消す記事")).to be_dismissed
    expect(Reading.count).to eq(0)

    find("#toast").click_on("元に戻す")
    expect(page).to have_css("article", count: 3)
    expect(all("article h2").map(&:text)).to eq(%w[上の記事 消す記事 下の記事])
    expect(page).to have_button("削除", count: 3)
    expect(Article.find_by!(title: "消す記事")).not_to be_dismissed

    choose "読む", allow_label_click: true
    expect(page).to have_no_button("削除")
  end

  it "続けて押すと押した分だけ消える（送信は 1 本ずつ）。指で押しても送られる" do
    titles = %w[一本目 二本目 三本目 四本目]
    titles.each_with_index { |title, i| create(:article, title: title, published_at: now - (i + 1).hours) }
    sign_in
    enter_delete_mode

    delete_row("一本目", native: true)
    delete_row("二本目")
    delete_row("三本目")

    expect(page).to have_css("article", count: 1)
    expect(page).to have_css("#toast [data-controller='toast']", count: 1)
    expect(page).to have_css("[data-unread-badge]", text: "1")
    expect(Article.where.not(dismissed_at: nil).pluck(:title)).to match_array(%w[一本目 二本目 三本目])
  end

  it "削除モードでは行を押しても広がらず、左右に引いても動かない。切り替えると広げていた欄は畳む" do
    create(:article, title: "広げた記事", summary: "・要約", published_at: now - 1.hour)
    create(:article, title: "触る記事", published_at: now - 2.hours)
    sign_in
    find("article", text: "広げた記事").find_button("読む").execute_script("this.click()")
    expect(page).to have_link("記事に遷移")

    enter_delete_mode
    expect(page).to have_no_link("記事に遷移")

    find("article", text: "触る記事").find_button("読む", visible: :all).execute_script("this.click()")
    width = card_width("触る記事")
    drag_card("触る記事", from: [ width / 2, 40 ], to: [ width / 2 + width * ratio * 1.3, 40 ], release: false)
    expect(card_shift("触る記事")).to eq(0)
    drag_card("触る記事", from: [ width / 2, 40 ], to: [ width / 2 - width * ratio * 1.3, 40 ], down: false)

    expect(page).to have_css("article", count: 2)
    expect(Article.find_by!(title: "触る記事").reading).to be_nil
    expect(Article.find_by!(title: "触る記事")).not_to be_bookmarked
  end

  it "画面を移って戻る・再読込すると「読む」で始まる" do
    create(:article, title: "記事", published_at: now - 1.hour)
    sign_in
    enter_delete_mode

    click_on "設定"
    expect(page).to have_css("h1", text: "設定")
    page.go_back
    expect(page).to have_checked_field("読む", visible: :all)
    expect(page).to have_no_button("削除")

    enter_delete_mode
    page.refresh
    expect(page).to have_checked_field("読む", visible: :all)
    expect(page).to have_no_button("削除")
  end

  it "未読が 0 本ならモードの切り替えは出ない" do
    sign_in
    expect(page).to have_text("全部読んだ。")
    expect(page).to have_no_field("削除", visible: :all)
  end
end
