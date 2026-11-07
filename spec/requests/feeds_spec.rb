RSpec.describe "Feeds", type: :request do
  it "未ログインでは一覧も削除も拒み、フィードを残す" do
    feed = create(:feed)
    get feeds_path
    expect(response).to redirect_to(new_session_path)
    expect { delete feed_path(feed) }.not_to change(Feed, :count)
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    around { |example| travel_to(Time.zone.local(2026, 11, 7, 12)) { example.run } }
    before { sign_in_as(create(:user)) }

    it "4 行に記事数・未読・取得状態を表示する" do
      feed = create(:feed, title: "Ruby Weekly", last_fetched_at: 3.minutes.ago)
      create(:article, :read, feed: feed)
      create(:article, :opened, feed: feed)
      create(:article, :dismissed, feed: feed)
      create(:article, feed: feed)
      create(:feed, title: "失敗", last_fetched_at: Time.current, last_error: "サーバーエラー (HTTP 503)")
      create_list(:feed, 2)
      get feeds_path
      page = Capybara.string(response.body)
      expect(page).to have_css("[data-feed]", count: 4)
      row = page.find("[data-feed]", text: "Ruby Weekly")
      expect(row).to have_text("4件・未読 2")
      expect(row).to have_text("最終取得 3分前")
      expect(row).to have_text(feed.url)
      expect(page).to have_css(".text-red-600", text: "サーバーエラー (HTTP 503)")
      expect(page).to have_text("未取得")
      expect(page).to have_css("[aria-current=page]", text: "購読")
    end

    it "対象の記事・保存・読了を消し、別フィードと達成済みの宝箱を残す" do
      article = create(:article, :liked, :bookmarked)
      other = create(:article)
      create(:reading, :completed, article: article, opened_at: Time.current - 1.hour)
      create(:reading, :completed, article: other, opened_at: Time.current - 1.day)
      create(:article, feed: article.feed)
      create(:article, feed: other.feed)
      goal = create(:daily_goal, :achieved, bonus_xp: 50)
      get root_path
      expect(Capybara.string(response.body)).to have_text("未読 2 件 ・ 読了 2")
      expect(response.body).to include("累計 70 XP", "2日連続")
      expect { delete feed_path(article.feed) }.to change(Feed, :count).by(-1)
        .and change(Article, :count).by(-2).and change(Reading, :count).by(-1)
      expect(response).to redirect_to(feeds_path)
      expect(other.reload.reading).to be_completed
      expect(goal.reload).to be_achieved
      get root_path
      expect(Capybara.string(response.body)).to have_text("未読 1 件 ・ 読了 1")
      expect(response.body).to include("累計 60 XP", "1日連続")
    end

    it "存在しないフィードの削除は 404" do
      delete feed_path(id: 0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
