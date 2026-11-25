RSpec.describe "Sweep", type: :system do
  let(:now) { Time.current }

  def sweep_button = find("button", text: /片付ける/)

  it "一覧の下の「残り n 件を片付ける」で見えている未読をまとめて消し、「元に戻す」で全部戻る。払った行は数から外れ、表示の後に届いた記事は消さない" do
    create(:article, title: "一本目", published_at: now - 1.hour)
    create(:article, title: "二本目", published_at: now - 2.hours)
    create(:article, title: "三本目", published_at: now - 3.hours)
    sign_in
    expect(sweep_button).to have_text("残り 3 件を片付ける")

    delete_row("二本目")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました")
    expect(sweep_button).to have_text("残り 2 件を片付ける")
    latest = create(:article, title: "後から届いた記事", published_at: now)
    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
    screenshot!("button")

    sweep_button.click
    expect(page).to have_css("#toast [data-controller='toast']", text: "2 件を片付けました")
    expect(page).to have_no_css("article")
    expect(page).to have_text("全部読んだ。")
    expect(page).to have_no_button("片付ける")
    expect(page).to have_css("[data-unread-badge]", text: "1")
    expect(Article.where.not(dismissed_at: nil).pluck(:title)).to match_array(%w[一本目 二本目 三本目])
    expect(latest.reload).not_to be_dismissed
    expect(Reading.count).to eq(0)
    screenshot!("swept")

    find("#toast").click_on("元に戻す")
    expect(all("article h2").map(&:text)).to eq(%w[一本目 三本目])
    expect(sweep_button).to have_text("残り 2 件を片付ける")
    expect(page).to have_css("[data-unread-badge]", text: "3")
    expect(Article.find_by!(title: "二本目")).to be_dismissed
  end

  it "処理モードで片付けても、コンボとリザルトには数えない" do
    create(:article, title: "払う記事", published_at: now - 1.hour)
    create(:article, title: "残る記事", published_at: now - 2.hours)
    sign_in
    enter_process_mode
    delete_row("払う記事")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました")
    expect(find("[data-process-mode-target='combo']")).to have_text("1 COMBO", normalize_ws: true)

    sweep_button.click
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を片付けました")
    expect(find("[data-process-mode-target='combo']")).to have_text("1 COMBO", normalize_ws: true)

    choose "読む", allow_label_click: true
    expect(find("dialog[open]", text: "リザルト")).to have_text("1 件 処理した", normalize_ws: true)
  end

  it "処理モードで片付けを元に戻しても、コンボは減らない" do
    create(:article, title: "払う記事", published_at: now - 1.hour)
    create(:article, title: "残る記事", published_at: now - 2.hours)
    sign_in
    enter_process_mode
    delete_row("払う記事")
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を削除しました")

    sweep_button.click
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を片付けました")
    find("#toast").click_on("元に戻す")
    expect(page).to have_css("article", text: "残る記事")
    expect(find("[data-process-mode-target='combo']")).to have_text("1 COMBO", normalize_ws: true)
  end

  it "一覧の中で読み終えた行は数えず、残りを片付けるとボタンが消える" do
    allow(Reading).to receive(:tier_at_open).and_return(Dopamine.rarity_names.first)
    create(:article, title: "読む記事", summary: "・要約", published_at: now - 1.hour)
    create(:article, title: "要らぬ記事", published_at: now - 2.hours)
    sign_in

    expand("読む記事")
    read_in_list("読む記事", dwell: Dopamine.settings.dig(:read, :complete_after_seconds) + 5)
    expect(page).to have_css("section[aria-label='判定']", text: "を手に入れた！")
    expect(sweep_button).to have_text("残り 1 件を片付ける")

    sweep_button.click
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件を片付けました")
    expect(page).to have_no_button("片付ける")
    expect(page).to have_css("article", text: "読む記事")
  end

  it "払った行が流れ出す途中に片付けても、片付けのトーストが残り、元に戻すで片付けた分が戻る" do
    create(:article, title: "一本目", published_at: now - 1.hour)
    create(:article, title: "二本目", published_at: now - 2.hours)
    create(:article, title: "三本目", published_at: now - 3.hours)
    sign_in

    delete_row("一本目")
    sweep_button.click
    expect(page).to have_css("#toast [data-controller='toast']", text: "2 件を片付けました")
    expect(page).to have_no_css("article")

    find("#toast").click_on("元に戻す")
    expect(all("article h2").map(&:text)).to eq(%w[二本目 三本目])
    expect(Article.find_by!(title: "一本目")).to be_dismissed
  end
end
