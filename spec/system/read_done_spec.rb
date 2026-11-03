# 読む → 記事 → 戻る → ReadDone → Main の動線を 390×844 で通す。
# 記事の URL は Capybara のサーバー（/up）にして、外に出ずに「記事を開いて戻る」を再現する
RSpec.describe "ReadDone", type: :system do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:base) { settings.dig(:xp, :base) }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:common) { Dopamine.tier_names.first }

  before { allow(XpRoulette).to receive(:draw).and_return(common) }

  def sign_in
    user = create(:user)
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  def article_on_this_server
    create(:article, title: "読む記事", url: "#{Capybara.current_session.server.base_url}/up")
  end

  it "読む → 戻るボタン → 自動で読了を記録 → ReadDone → 閉じるとカードが消えドットが 1 つ塗られる" do
    article = article_on_this_server
    sign_in
    click_on "読む"
    expect(page).to have_current_path("/up")

    travel_to(Time.current + threshold + 5.seconds) do
      page.go_back
      expect(page).to have_text("読了！"), "戻る（back_forward）で reading-return が自動送信するはず"
      expect(page).to have_text("判定 完読")
      expect(page).to have_text("合計 +#{base} XP")
      expect(page).to have_text("今日のゴール 1 / #{goal_articles}")
      expect(page).to have_text("全部読んだ")

      click_on "閉じる"
      expect(page).to have_current_path(root_path)
      expect(page).to have_no_text("読む記事")
      expect(page).to have_css(".goal-dot[data-filled=true]", count: 1)
      expect(page).to have_text("読了 1")
    end
    expect(article.reload.reading).to be_completed
  end

  it "開いて戻っていない記事は Main のピルから手で記録でき、短ければ未完" do
    article = article_on_this_server
    sign_in
    click_on "読む"
    expect(page).to have_current_path("/up")

    visit root_path
    expect(page).to have_button("読了を記録")
    click_on "読了を記録"

    expect(page).to have_text("判定 未完")
    expect(page).to have_text("合計 +0 XP")
    expect(article.reload.reading).not_to be_completed
    expect(article.reading.returned_at).to be_present
  end
end
