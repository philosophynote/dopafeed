RSpec.describe "区切りの見せ場", type: :system do
  let(:threshold) { Dopamine.settings.dig(:read, :complete_after_seconds) }
  let(:fever) { Dopamine.settings.dig(:cards, :fever_combo) }
  let(:common) { Dopamine.rarity_names.first }
  let(:feed) { create(:feed, title: "いつものフィード") }

  before { allow(RarityDraw).to receive(:draw).and_return(common) }

  def banner
    find("section[aria-label='判定'] [role='status']")
  end

  def earlier_cards(count, minutes_ago: 30)
    count.times { |i| create(:reading, :completed, article: create(:article, feed: feed), opened_at: Time.current - (minutes_ago - i).minutes) }
  end

  it "今日の 1 枚目は、一番大きい見せ場を大きく出し、残りを 1 行に畳む。押すと動きが止まり文字は残る。図鑑の枚数が弾む" do
    create(:article, title: "今日の 1 本", feed: feed, summary: "・要約")
    sign_in

    expand("今日の 1 本")
    read_in_list("今日の 1 本", dwell: threshold + 5)

    expect(banner["data-highlight"]).to eq("new_feed")
    expect(banner).to have_text("NEW FEED!")
    expect(banner.find("[data-highlight-rest]")).to have_text("FIRST CARD!")
    expect(find("#status-card [data-cards-count]")[:class]).to include("count-pop")
    screenshot!("first")

    banner.click
    expect(banner[:class]).to include("is-settled")
    expect(banner).to have_text("NEW FEED!")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
  end

  it "2 枚目からは n 連続が出て、FEVER の本数に届くと虹色の FEVER とステータスの虹色のバッジになる" do
    earlier_cards(fever - 2)
    create(:article, title: "連続の記事", feed: feed, summary: "・要約", published_at: 1.hour.ago)
    create(:article, title: "FEVER の記事", feed: feed, summary: "・要約", published_at: 2.hours.ago)
    sign_in

    expand("連続の記事")
    read_in_list("連続の記事", dwell: threshold + 5)
    expect(banner).to have_text("#{fever - 1} 連続！")
    expect(banner["data-tier"]).to eq("medium")

    expand("FEVER の記事")
    read_in_list("FEVER の記事", dwell: threshold + 5)
    expect(find("li[id^='article_']", text: "FEVER の記事").find("[role='status']")).to have_text("FEVER! #{fever} 連続")
    expect(find("li[id^='article_']", text: "FEVER の記事").find("[role='status']")[:class]).to include("highlight-fever")
    expect(find("#status-card [data-combo]")[:class]).to include("fever-badge")
    screenshot!("fever")
  end

  it "カードにならなかったら煙が上がり、見せ場は出ない" do
    create(:article, title: "すぐ戻る記事", feed: feed, summary: "・要約")
    sign_in

    expand("すぐ戻る記事")
    read_in_list("すぐ戻る記事", dwell: 1)

    expect(page).to have_css("section[aria-label='判定'] .smoke", visible: :all)
    expect(page).to have_no_css("section[aria-label='判定'] [role='status']")
    expect(find("#status-card [data-cards-count]")[:class]).not_to include("count-pop")
  end

  it "Reader で金と NEW RECORD が重なると、全画面の開封に残りを 1 行で畳み、区切りの見せ場は NEW RECORD を先頭に出す" do
    3.times { |i| create(:reading, :completed, article: create(:article, feed: feed), opened_at: 2.days.ago + (i * 10).minutes) }
    earlier_cards(3)
    allow(RarityDraw).to receive(:draw).and_return(Dopamine.top_rarity[:name])
    article = create(:article, title: "金の記事", feed: feed, url: "#{Capybara.current_session.server.base_url}/up?gold", summary: "・要約")
    article.bookmark!
    sign_in
    visit saved_path
    within("article", text: "金の記事") { click_on "読む" }
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

    overlay = find("[role='dialog'][aria-label='金のカードの開封']")
    expect(overlay.find("[data-highlight-rest]")).to have_text("NEW RECORD! 4 連続 ・ 4 連続！")
    screenshot!("gold")
    overlay.click
    expect(banner["data-highlight"]).to eq("new_record")
    expect(banner.find("[data-highlight-rest]")).to have_text("金のカード！ ・ 4 連続！")
  end

  it "判定済みの区切りを再読込しても、見せ場は出ない（数えるのは判定した直後だけ）" do
    article = create(:article, title: "読んだ記事", feed: feed, url: "#{Capybara.current_session.server.base_url}/up?read", summary: "・要約")
    sign_in
    read_from_saved(article)
    page.execute_script(<<~JS)
      document.addEventListener("click", (event) => { if (event.target.closest("a[target=_blank]")) event.preventDefault() }, true)
    JS
    reading = article.reload.reading
    since = reading.opened_at
    click_on "記事を開く"
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until reading.reload.opened_at > since }
    reading.update_columns(opened_at: Time.current - threshold - 5)
    click_on "読み終えた"
    expect(banner).to have_text("NEW FEED!")

    page.refresh
    expect(page).to have_css("section[aria-label='判定']", text: "を手に入れた！")
    expect(page).to have_no_css("section[aria-label='判定'] [role='status']")
  end
end
