# Main のカードを読まずに片付ける（docs/screens/swipe.md）。「興味なし」で消え、「元に戻す」で戻る、を 390×844 で通す
RSpec.describe "Swipe", type: :system do
  let(:now) { Time.current }

  it "「興味なし」でカードが帯に替わり未読数が減り、「元に戻す」でカードが戻る" do
    create(:article, title: "関心の無い記事", published_at: now - 1.hour)
    create(:article, title: "読みたい記事", published_at: now - 2.hours)
    sign_in

    expect(page).to have_text("未読 2 件")
    within("article", text: "関心の無い記事") { click_on "興味なし" }

    # 帯は見出しだけを省略するために 3 つの span に分かれ、見える文字は改行を挟んで読まれる。文として一致させず、帯の中に見出しがあることを見る
    strip = find("li", text: "を興味なしにした")
    expect(strip).to have_text("関心の無い記事")
    expect(strip).to have_button("元に戻す")
    expect(page).to have_css("article", count: 1)
    expect(page).to have_text("未読 1 件")
    expect(page).to have_css("[data-unread-badge]", text: "1")
    expect(Article.find_by(title: "関心の無い記事")).to be_dismissed
    screenshot!("dismissed")

    click_on "元に戻す"

    expect(page).to have_css("article", count: 2)
    expect(page).to have_no_text("を興味なしにした")
    expect(page).to have_text("未読 2 件")
    expect(Article.find_by(title: "関心の無い記事")).not_to be_dismissed
  end
end
