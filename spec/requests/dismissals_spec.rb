# 「興味なし」（POST /articles/:id/dismissal）と「元に戻す」（DELETE）。docs/screens/swipe.md の受け入れ条件のうち、記録と片付け
RSpec.describe "Dismissals", type: :request do
  include ActionView::RecordIdentifier

  let(:noon) { Time.zone.local(2026, 10, 20, 12) }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  # turbo-stream の中身は <template> に包まれ、HTML4 の parser は template の子を捨てるので外して読む
  def page
    Capybara.string(response.body.gsub(%r{</?template>}, ""))
  end

  it "未ログインならログイン画面へ" do
    article = create(:article)
    post article_dismissal_path(article)
    expect(response).to redirect_to(new_session_path)

    delete article_dismissal_path(article)
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    describe "興味なし（POST）" do
      let!(:article) { create(:article, title: "関心の無い記事") }
      let!(:other) { create(:article) }

      it "dismissed_at を今にし、Turbo Stream でカードを「元に戻す」の帯に替え、未読数を減らす" do
        travel_to(noon) { post article_dismissal_path(article), headers: turbo }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(article.reload.dismissed_at).to eq(noon)

        card = page.find("turbo-stream[action='replace'][target='#{dom_id(article)}']")
        expect(card).to have_text("「関心の無い記事」を興味なしにした")
        expect(card).to have_button("元に戻す")
        expect(card).to have_no_button("読む")
        expect(page.find("turbo-stream[action='update'][target='unread-count']")).to have_text("1")
        expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_css("[data-unread-badge]", text: "1")
      end

      it "Reading を作らず、読了・XP・今日のゴール・コンボ・ストリークを変えない" do
        create(:reading, :completed, opened_at: noon - 1.hour)
        before = travel_to(noon) { [ Reading.completed.sum(:xp), Reading.on(ReadingDay.of).count, Combo.new.multiplier, ReadingStreak.days ] }

        travel_to(noon) do
          expect { post article_dismissal_path(article), headers: turbo }.not_to change(Reading, :count)
          expect(article.reload.reading).to be_nil
          expect([ Reading.completed.sum(:xp), Reading.on(ReadingDay.of).count, Combo.new.multiplier, ReadingStreak.days ]).to eq(before)
        end
      end

      it "無い記事なら 404" do
        post article_dismissal_path(article_id: 0), headers: turbo
        expect(response).to have_http_status(:not_found)
      end

      it "開いたが未完の記事なら Reading は残したまま未読から外す" do
        opened = create(:article, :opened)

        post article_dismissal_path(opened), headers: turbo

        expect(opened.reload).to be_dismissed
        expect(opened.reading).to be_present
        expect(opened.reading).not_to be_completed
      end

      it "最後の 1 本を興味なしにすると未読数は 0 でバッジが消える" do
        other.dismiss!

        post article_dismissal_path(article), headers: turbo

        expect(page.find("turbo-stream[action='update'][target='unread-count']")).to have_text("0")
        expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_no_css("[data-unread-badge]")
      end

      it "JS が無ければ Main へ戻る" do
        post article_dismissal_path(article)

        expect(response).to redirect_to(root_path)
        expect(article.reload).to be_dismissed
      end
    end

    describe "元に戻す（DELETE）" do
      let!(:article) { create(:article, :dismissed, title: "戻す記事") }

      it "dismissed_at を消し、Turbo Stream で帯をカードに戻し、未読数を増やす" do
        delete article_dismissal_path(article), headers: turbo

        expect(response).to have_http_status(:ok)
        expect(article.reload).not_to be_dismissed

        card = page.find("turbo-stream[action='replace'][target='#{dom_id(article)}']")
        expect(card).to have_css("article h2", text: "戻す記事")
        expect(card).to have_button("読む")
        expect(card).to have_button("興味なし")
        expect(card).to have_no_button("元に戻す")
        expect(page.find("turbo-stream[action='update'][target='unread-count']")).to have_text("1")
        expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_css("[data-unread-badge]", text: "1")
      end

      it "JS が無ければ Main へ戻る" do
        delete article_dismissal_path(article)

        expect(response).to redirect_to(root_path)
        expect(article.reload).not_to be_dismissed
      end
    end
  end
end
