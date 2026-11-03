# Main を 390×844 で開く。見た目の崩れ（横スクロール・タップ領域）と、ログイン → Main → 設定 → サインアウトの動線
RSpec.describe "Main", type: :system do
  let(:goal_articles) { Dopamine.settings.dig(:daily_goal, :articles) }
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }

  def sign_in
    user = create(:user)
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  it "未読 3 本と今日のゴール 3 / N が出て、横スクロールが無く、タップ領域は 44px 以上" do
    feed = create(:feed, title: "Ruby Weekly")
    3.times { |i| create(:article, feed: feed, title: "記事 #{i + 1} のとても長い見出しが 390 幅で折り返されること", published_at: noon - i.hours) }
    travel_to noon do
      3.times { create(:reading, :completed, opened_at: noon - 1.hour) }
      sign_in

      expect(page).to have_css("article", count: 3)
      expect(page).to have_text("今日のゴール 3 / #{goal_articles}")
      expect(page).to have_text("1日連続")

      expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
      small = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll("a, button")).map(el => {
          const r = el.getBoundingClientRect();
          return [el.textContent.trim() || el.getAttribute("aria-label"), Math.round(r.width), Math.round(r.height)];
        }).filter(([, w, h]) => w < 44 || h < 44)
      JS
      expect(small).to be_empty, "44px 未満のタップ領域: #{small.inspect}"
    end
  end

  it "未読 0 本なら空状態が出る" do
    create(:article, :read)
    sign_in

    expect(page).to have_text("全部読んだ。")
    expect(page).to have_text("次の記事が届くまで、今日はここまで。")
    expect(page).to have_no_css("article")
  end

  it "設定からサインアウトするとログイン画面へ" do
    sign_in

    click_on "設定"
    expect(page).to have_css("h1", text: "設定")

    click_on "サインアウト"
    expect(page).to have_current_path(new_session_path)
  end
end
