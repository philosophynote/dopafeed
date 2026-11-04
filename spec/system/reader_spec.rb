# 読む → Roulette → アプリ内のリーダー → 末尾までスクロール → 判定と次の記事が継ぎ足される、を 390×844 で通す。
# 滞在は travel_to ではなく opened_at を書き換えて作る（ブラウザの時計とずれないように）
RSpec.describe "Reader", type: :system do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:base) { settings.dig(:xp, :base) }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:common) { Dopamine.tier_names.first }
  let(:now) { Time.current }

  before { allow(XpRoulette).to receive(:draw).and_return(common) }

  # 390×844 で末尾が最初は画面の外にある長さの本文。横に長いコードも入れて、はみ出さないことを見る
  def long_content(label)
    paragraphs = Array.new(30) { |i| "<p>#{label}の段落 #{i + 1}。読み進めると末尾の「読み終えた」が近づく。</p>" }
    "<h2>#{label}の見出し</h2>#{paragraphs.join}<pre><code>#{"x" * 200}</code></pre>"
  end

  def no_horizontal_scroll?
    page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
  end

  def make_dwell(reading, seconds)
    reading.reload.update_columns(opened_at: Time.current - seconds)
  end

  it "読むと本文がアプリ内で開き、末尾までスクロールすると判定と次の記事が下に継ぎ足され、続けて読める" do
    first = create(:article, title: "最初の記事", published_at: now - 1.hour, content: long_content("最初"), content_fetched_at: now)
    second = create(:article, title: "次の記事", published_at: now - 2.hours, content: long_content("次"), content_fetched_at: now)
    sign_in

    within("article", text: "最初の記事") { click_on "読む" }
    expect(page).to have_current_path(read_article_path(first))
    expect(page).to have_css(".reader-body h2", text: "最初の見出し")
    expect(page).to have_no_css("section[aria-label='判定']")
    expect(no_horizontal_scroll?).to be(true), "本文が横にはみ出している"
    screenshot!("body")

    make_dwell(first.reading, threshold + 5)
    page.scroll_to(find("form#end_reading_#{first.reading.id}"))

    expect(page).to have_css("section[aria-label='判定']", text: "読了！ +#{base} XP")
    expect(page).to have_text("今日のゴール 1 / #{goal_articles}")
    expect(page).to have_css("h1", text: "次の記事")
    expect(page).to have_current_path(read_article_path(first))
    expect(first.reload.reading).to be_completed
    screenshot!("divider")

    # 次の記事は継ぎ足された瞬間に開いている。すぐ末尾まで流すと未完で、未読が尽きたら「全部読んだ」
    page.scroll_to(find("form#end_reading_#{second.reload.reading.id}"))
    expect(page).to have_css("section[aria-label='判定']", text: "未完 ・ +0 XP")
    expect(page).to have_text("全部読んだ")
    expect(second.reading.reload).not_to be_completed
    expect(no_horizontal_scroll?).to be(true)
    screenshot!("all_read")

    click_on "閉じる", match: :first
    expect(page).to have_current_path(root_path)
    expect(page).to have_no_text("最初の記事")
    expect(page).to have_text("次の記事")
  end

  it "最初から末尾が見えている短い記事は自動で送らず、「読み終えた」で判定する" do
    article = create(:article, title: "短い記事", summary: "・一\n・二\n・三")
    sign_in

    click_on "読む"
    expect(page).to have_current_path(read_article_path(article))
    expect(page).to have_text("本文を取れなかった")
    expect(page).to have_link("元記事で読む", href: article.url)
    expect(page).to have_button("読み終えた")
    expect(article.reload.reading.returned_at).to be_nil

    make_dwell(article.reading, threshold + 5)
    click_on "読み終えた"

    expect(page).to have_css("section[aria-label='判定']", text: "読了！")
    expect(page).to have_text("全部読んだ")
    expect(article.reading.reload).to be_completed
  end
end
