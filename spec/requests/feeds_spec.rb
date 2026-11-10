RSpec.describe "Feeds", type: :request do
  include ActionView::RecordIdentifier

  it "未ログインでは一覧も削除も拒み、フィードを残す" do
    feed = create(:feed)
    get feeds_path
    expect(response).to redirect_to(new_session_path)
    get new_feed_path
    expect(response).to redirect_to(new_session_path)
    expect { post feeds_path, params: { feed: { url: "https://example.com/feed" } } }.not_to change(Feed, :count)
    expect(response).to redirect_to(new_session_path)
    expect { delete feed_path(feed) }.not_to change(Feed, :count)
    expect(response).to redirect_to(new_session_path)
    get edit_feed_path(feed)
    expect(response).to redirect_to(new_session_path)
    expect { patch feed_path(feed), params: { feed: { title: "乗っ取り" } } }.not_to change { feed.reload.title }
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    around { |example| travel_to(Time.zone.local(2026, 11, 7, 12)) { example.run } }
    before { sign_in_as(create(:user)) }

    it "シートの戻り先として任意の URL を使わない" do
      get new_feed_path(from: "https://example.com/")
      expect(Capybara.string(response.body)).to have_link("閉じる", href: feeds_path)
      expect(Capybara.string(response.body)).to have_css("turbo-frame#turbo_add_feed", count: 1)
    end

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
      goal = create(:daily_goal, :achieved)
      get root_path
      expect(Capybara.string(response.body)).to have_css("[data-unread-badge]", text: "2")
      expect(Capybara.string(response.body)).to have_text("2 枚", normalize_ws: true).and have_text("2日連続")
      expect { delete feed_path(article.feed) }.to change(Feed, :count).by(-1)
        .and change(Article, :count).by(-2).and change(Reading, :count).by(-1)
      expect(response).to redirect_to(feeds_path)
      expect(other.reload.reading).to be_completed
      expect(goal.reload).to be_achieved
      get root_path
      expect(Capybara.string(response.body)).to have_css("[data-unread-badge]", text: "1")
      expect(Capybara.string(response.body)).to have_text("1 枚", normalize_ws: true).and have_text("1日連続")
    end

    it "存在しないフィードの削除は 404" do
      delete feed_path(id: 0)
      expect(response).to have_http_status(:not_found)
    end

    describe "名前の変更" do
      let(:feed) { create(:feed, title: "元の名前") }
      let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

      def page
        Capybara.string(response.body.gsub(%r{</?template>}, ""))
      end

      it "一覧の行のタイトルと「名前を変更」は行ごとの Frame の中にある" do
        feed
        get feeds_path
        frame = page.find("[data-feed] turbo-frame##{dom_id(feed, :title)}")
        expect(frame).to have_css("h2", text: "元の名前")
        expect(frame).to have_link("名前を変更", href: edit_feed_path(feed))
      end

      it "入力欄は今の名前入りで、同じ Frame に描く" do
        get edit_feed_path(feed)
        frame = page.find("turbo-frame##{dom_id(feed, :title)}")
        expect(frame).to have_field("名前", with: "元の名前") { |field| field[:required] }
        expect(frame).to have_button("保存")
        expect(frame).to have_link("やめる", href: feeds_path)
      end

      it "前後の空白を落として保存し、JS が無ければ一覧へ戻る" do
        patch feed_path(feed), params: { feed: { title: "  新しい名前 " } }
        expect(response).to redirect_to(feeds_path)
        expect(feed.reload.title).to eq("新しい名前")
      end

      it "IME の全角空白も前後なら落とし、間の空白は残す" do
        patch feed_path(feed), params: { feed: { title: "\u3000Zenn　トレンド\u3000 " } }
        expect(feed.reload.title).to eq("Zenn　トレンド")
      end

      it "JS が無くても空白だけなら 422 で入力欄に赤字を出す" do
        patch feed_path(feed), params: { feed: { title: "\u3000" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(page).to have_css(".text-red-600", text: "名前を入力してください")
        expect(feed.reload.title).to eq("元の名前")
      end

      it "Turbo の要求には行を差し替える Turbo Stream を返し、件数と削除の確認文も新しい名前で描く" do
        create(:article, :read, feed: feed)
        create(:article, feed: feed)

        patch feed_path(feed), params: { feed: { title: "新しい名前" } }, headers: turbo

        row = page.find("turbo-stream[action='replace'][target='#{dom_id(feed)}'] li[data-feed]")
        expect(row).to have_css("h2", text: "新しい名前")
        expect(row).to have_text("2件・未読 1")
        expect(row).to have_css("form[data-turbo-confirm^='「新しい名前」を削除しますか？']")
      end

      it "空なら 422 で入力欄に赤字を出し、名前は元のまま" do
        patch feed_path(feed), params: { feed: { title: "   " } }, headers: turbo

        expect(response).to have_http_status(:unprocessable_content)
        frame = page.find("turbo-frame##{dom_id(feed, :title)}")
        expect(frame).to have_css(".text-red-600", text: "名前を入力してください")
        expect(frame).to have_field("名前")
        expect(feed.reload.title).to eq("元の名前")
      end

      it "名前のほかは変えない" do
        url = feed.url
        patch feed_path(feed), params: { feed: { title: "新しい名前", url: "https://other.example.com/feed" } }
        expect(feed.reload).to have_attributes(title: "新しい名前", url: url)
      end

      it "存在しないフィードは 404" do
        get edit_feed_path(id: 0)
        expect(response).to have_http_status(:not_found)
        patch feed_path(id: 0), params: { feed: { title: "x" } }
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
