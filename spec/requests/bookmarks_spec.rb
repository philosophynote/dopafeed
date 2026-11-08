# 「保存」（POST /articles/:id/bookmark）と「元に戻す」（DELETE）。docs/screens/saved.md の受け入れ条件のうち、Main での記録と片付け
RSpec.describe "Bookmarks", type: :request do
  include ActionView::RecordIdentifier

  let(:noon) { Time.zone.local(2026, 10, 20, 12) }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  # turbo-stream の中身は <template> に包まれ、HTML4 の parser は template の子を捨てるので外して読む
  def page
    Capybara.string(response.body.gsub(%r{</?template>}, ""))
  end

  it "未ログインならログイン画面へ" do
    article = create(:article)
    post article_bookmark_path(article)
    expect(response).to redirect_to(new_session_path)

    delete article_bookmark_path(article)
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    describe "保存（POST）" do
      let!(:article) { create(:article, title: "あとで読む記事") }
      let!(:other) { create(:article) }

      it "bookmarked_at を今にし、Turbo Stream で行を「元に戻す」の帯に替え、未読数を減らす" do
        travel_to(noon) { post article_bookmark_path(article), headers: turbo }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(article.reload.bookmarked_at).to eq(noon)

        band = page.find("turbo-stream[action='replace'][target='#{dom_id(article)}']")
        expect(band).to have_text("「あとで読む記事」を保存した")
        expect(band).to have_button("元に戻す")
        expect(band).to have_no_button("読む")
        expect(page).to have_no_css("turbo-stream[target='unread-count']")
        expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_css("[data-unread-badge]", text: "1")
        expect(page).to have_css("turbo-stream[action='replace'][target='app-badge'] #app-badge[data-badge-count-value='1']", visible: :all)
      end

      it "Reading を作らず、読了（カード）・今日のゴール・コンボ・ストリークを変えない" do
        create(:reading, :completed, opened_at: noon - 1.hour)
        before = travel_to(noon) { [ Reading.completed.count, Reading.on(ReadingDay.of).count, Combo.new.count, ReadingStreak.days ] }

        travel_to(noon) do
          expect { post article_bookmark_path(article), headers: turbo }.not_to change(Reading, :count)
          expect(article.reload.reading).to be_nil
          expect([ Reading.completed.count, Reading.on(ReadingDay.of).count, Combo.new.count, ReadingStreak.days ]).to eq(before)
        end
      end

      it "無い記事なら 404" do
        post article_bookmark_path(article_id: 0), headers: turbo
        expect(response).to have_http_status(:not_found)
      end

      it "JS が無ければ Main へ戻る" do
        post article_bookmark_path(article)

        expect(response).to redirect_to(root_path)
        expect(article.reload).to be_bookmarked
      end
    end

    describe "元に戻す（DELETE）" do
      let!(:article) { create(:article, :bookmarked, title: "戻す記事") }

      it "bookmarked_at を消し、Turbo Stream で帯を行に戻し、未読数を増やす" do
        delete article_bookmark_path(article), headers: turbo

        expect(response).to have_http_status(:ok)
        expect(article.reload).not_to be_bookmarked

        card = page.find("turbo-stream[action='replace'][target='#{dom_id(article)}']")
        expect(card).to have_css("article h2", text: "戻す記事")
        expect(card).to have_button("「戻す記事」を読む")
        expect(card).to have_no_button("元に戻す")
        expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_css("[data-unread-badge]", text: "1")
      end

      it "保存した後に読み終えていた記事は、行を戻さず帯だけ消す（未読ではない）" do
        read = create(:article, :bookmarked, :read, title: "読み終えた記事")

        delete article_bookmark_path(read), headers: turbo

        expect(read.reload).not_to be_bookmarked
        expect(page).to have_css("turbo-stream[action='remove'][target='#{dom_id(read)}']")
        expect(page).to have_no_css("turbo-stream[action='replace'][target='#{dom_id(read)}']")
      end

      it "興味なしでもある記事は未読に戻らないので、行を戻さず帯だけ消す" do
        both = create(:article, :bookmarked, :dismissed)

        delete article_bookmark_path(both), headers: turbo

        expect(page).to have_css("turbo-stream[action='remove'][target='#{dom_id(both)}']")
        expect(page).to have_no_css("turbo-stream[action='replace'][target='#{dom_id(both)}']")
      end

      it "JS が無ければ Main へ戻る" do
        delete article_bookmark_path(article)

        expect(response).to redirect_to(root_path)
        expect(article.reload).not_to be_bookmarked
      end
    end
  end
end
