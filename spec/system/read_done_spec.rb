# 読みかけのまま Main に戻った記事を、Main のピルから手で記録して ReadDone を出す動線を 390×844 で通す
RSpec.describe "ReadDone", type: :system do
  let(:common) { Dopamine.tier_names.first }

  before { allow(XpRoulette).to receive(:draw).and_return(common) }

  it "リーダーを途中で閉じた記事は Main のピルから手で記録でき、短ければ未完" do
    article = create(:article, title: "読みかけの記事")
    sign_in
    click_on "読む"
    expect(page).to have_current_path(read_article_path(article))

    click_on "閉じる"
    expect(page).to have_button("読了を記録")
    click_on "読了を記録"

    expect(page).to have_text("判定 未完")
    expect(page).to have_text("合計 +0 XP")
    expect(article.reload.reading).not_to be_completed
    expect(article.reading.returned_at).to be_present
  end
end
