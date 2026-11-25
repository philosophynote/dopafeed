RSpec.describe "Sweeps", type: :request do
  include ActionView::RecordIdentifier

  let(:noon) { Time.zone.local(2026, 10, 20, 12) }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  # HTML4 の parser は template の子を捨てるため、Turbo Stream の template を外して読む。
  def page
    Capybara.string(response.body.gsub(%r{</?template>}, ""))
  end

  it "未ログインならログイン画面へ" do
    article = create(:article)
    post sweep_path, params: { article_ids: [ article.id ] }
    expect(response).to redirect_to(new_session_path)

    delete sweep_path, params: { article_ids: [ article.id ] }
    expect(response).to redirect_to(new_session_path)
    expect(article.reload).not_to be_dismissed
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    describe "片付ける（POST）" do
      let!(:first) { create(:article, title: "一本目") }
      let!(:second) { create(:article, title: "二本目") }

      it "送られた未読の記事を同じ時刻で削除し、行を跡に替えて「n 件を片付けました」のトーストを出し、未読数を書き直す" do
        latest = create(:article, title: "後から届いた記事")

        travel_to(noon) { post sweep_path, params: { article_ids: [ first.id, second.id ] }, headers: turbo }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect([ first.reload.dismissed_at, second.reload.dismissed_at ]).to eq([ noon, noon ])
        expect(latest.reload).not_to be_dismissed
        [ first, second ].each do |article|
          row = page.find("turbo-stream[action='replace'][target='#{dom_id(article)}']", visible: :all)
          expect(row).to have_css("li##{dom_id(article)}[hidden]", visible: :all)
        end
        toast = page.find("turbo-stream[action='update'][target='toast']")
        expect(toast).to have_css("[data-controller='toast']", text: "2 件を片付けました")
        undo = toast.find("form[action='#{sweep_path}']")
        expect(undo).to have_css("input[name='_method'][value='delete']", visible: :all)
        expect(undo.all("input[name='article_ids[]']", visible: :all).map(&:value)).to contain_exactly(first.id.to_s, second.id.to_s)
        expect(toast).to have_button("元に戻す")
        expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_css("[data-unread-badge]", text: "1")
        expect(page).to have_css("turbo-stream[action='replace'][target='app-badge'] #app-badge[data-badge-count-value='1']", visible: :all)
      end

      it "押す前に削除・保存・完読した記事は消さず、元に戻すにも入れない" do
        dismissed = create(:article, :dismissed)
        saved = create(:article, :bookmarked)
        read = create(:article, :read)

        post sweep_path, params: { article_ids: [ first.id, dismissed.id, saved.id, read.id ] }, headers: turbo

        expect(first.reload).to be_dismissed
        expect(dismissed.reload.dismissed_at).to eq(Time.zone.local(2026, 10, 5, 12))
        expect(saved.reload).not_to be_dismissed
        expect(read.reload).not_to be_dismissed
        expect(page.find("turbo-stream[target='toast']")).to have_css("[data-controller='toast']", text: "1 件を片付けました")
        expect(page.all("turbo-stream[target='toast'] input[name='article_ids[]']", visible: :all).map(&:value)).to eq([ first.id.to_s ])
        expect(page).to have_no_css("turbo-stream[target='#{dom_id(saved)}']")
        expect(page).to have_no_css("turbo-stream[target='#{dom_id(read)}']")
      end

      it "開いたが未完の記事も消し、Reading は残す" do
        opened = create(:article, :opened)

        post sweep_path, params: { article_ids: [ opened.id ] }, headers: turbo

        expect(opened.reload).to be_dismissed
        expect(opened.reading).to be_present
      end

      it "読了（カード）・今日のゴール・コンボ・ストリークを変えない" do
        create(:reading, :completed, opened_at: noon - 1.hour)
        before = travel_to(noon) { [ Reading.on(ReadingDay.of).count, Combo.new.count, ReadingStreak.days ] }

        travel_to(noon) do
          expect { post sweep_path, params: { article_ids: [ first.id, second.id ] }, headers: turbo }.not_to change(Reading, :count)
          expect([ Reading.on(ReadingDay.of).count, Combo.new.count, ReadingStreak.days ]).to eq(before)
        end
      end

      it "スワイプと同じ送信の番号（swipe）をトーストに渡す" do
        post sweep_path, params: { article_ids: [ first.id ], swipe: 4 }, headers: turbo

        expect(page).to have_css("turbo-stream[target='toast'] [data-controller='toast'][data-toast-swipe-value='4']", visible: :all)
      end

      it "消せる記事が 1 本も無ければトーストを出さない" do
        first.dismiss!

        post sweep_path, params: { article_ids: [ first.id ] }, headers: turbo

        expect(response).to have_http_status(:ok)
        expect(page).to have_no_css("turbo-stream[target='toast']")
        expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_css("[data-unread-badge]", text: "1")
      end

      it "id が送られなければ何も消さない" do
        post sweep_path, headers: turbo

        expect(Article.unread.count).to eq(2)
        expect(page).to have_no_css("turbo-stream[target='toast']")
      end

      it "JS が無ければ Main へ戻る" do
        post sweep_path, params: { article_ids: [ first.id, second.id ] }

        expect(response).to redirect_to(root_path)
        expect(Article.unread.count).to eq(0)
      end
    end

    describe "元に戻す（DELETE）" do
      let!(:first) { create(:article, :dismissed, title: "戻す一本目") }
      let!(:second) { create(:article, :dismissed, title: "戻す二本目") }

      it "送られた記事の dismissed_at を消し、跡を行に戻してトーストを消し、未読数を書き直す" do
        untouched = create(:article, :dismissed)

        delete sweep_path, params: { article_ids: [ first.id, second.id ] }, headers: turbo

        expect(response).to have_http_status(:ok)
        expect([ first.reload, second.reload ]).to all(satisfy { |article| !article.dismissed? })
        expect(untouched.reload).to be_dismissed
        { first => "戻す一本目", second => "戻す二本目" }.each do |article, title|
          card = page.find("turbo-stream[action='replace'][target='#{dom_id(article)}']")
          expect(card).to have_css("article h2", text: title)
          expect(card).to have_button("「#{title}」を読む")
        end
        expect(page.find("turbo-stream[action='update'][target='toast']", visible: :all).text(:all)).to be_blank
        expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_css("[data-unread-badge]", text: "2")
      end

      it "片付けた後に保存も入った記事は、行を戻さず跡を消す（未読ではない）" do
        first.update!(bookmarked_at: noon)

        delete sweep_path, params: { article_ids: [ first.id, second.id ] }, headers: turbo

        expect(page).to have_css("turbo-stream[action='remove'][target='#{dom_id(first)}']")
        expect(page).to have_css("turbo-stream[action='replace'][target='#{dom_id(second)}']")
      end

      it "JS が無ければ Main へ戻る" do
        delete sweep_path, params: { article_ids: [ first.id, second.id ] }

        expect(response).to redirect_to(root_path)
        expect(Article.unread.count).to eq(2)
      end
    end
  end
end
