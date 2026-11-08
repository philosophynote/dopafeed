# Saved（GET /saved）。docs/screens/saved.md の受け入れ条件のうち、描画で確かめられるもの
RSpec.describe "Saved", type: :request do
  def page
    Capybara.string(response.body)
  end

  it "未ログインならログイン画面へ" do
    get saved_path
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "保存した記事だけを「保存 (N)」と保存した新しい順に並べる。いいねだけ・未保存の記事は出さない" do
      create(:article, title: "先に保存", bookmarked_at: Time.zone.local(2026, 10, 1, 9))
      create(:article, title: "後に保存", bookmarked_at: Time.zone.local(2026, 10, 3, 9))
      create(:article, :liked, title: "いいねだけ")
      create(:article, title: "未保存")

      get saved_path

      expect(response).to have_http_status(:ok)
      expect(page).to have_css("h1", text: "保存 (2)")
      expect(page.all("article h2").map(&:text)).to eq(%w[後に保存 先に保存])
    end

    it "未読の行は Main と同じく行全体が「読む」の POST" do
      article = create(:article, :bookmarked, title: "未読の記事")

      get saved_path

      expect(page.find("article").find("form[action='#{article_reading_path(article)}']")).to have_button("「未読の記事」を読む")
      expect(page.find("article")).to have_no_text("読んだ")
    end

    it "読み終えた行は「読んだ」の印を付け、抽選し直さずに Reader を開くリンクにする" do
      article = create(:article, :bookmarked, :read, title: "読んだ記事")

      get saved_path

      row = page.find("article")
      expect(row).to have_text("読んだ")
      expect(row).to have_link("「読んだ記事」を開く", href: read_article_path(article))
      expect(row).to have_no_css("form[action='#{article_reading_path(article)}']")
    end

    it "行は引いて保存を外せる。保存を外す form は見えるボタンにせず、スワイプが送る" do
      article = create(:article, :bookmarked)

      get saved_path

      row = page.find("li##{ActionView::RecordIdentifier.dom_id(article)}[data-controller='swipe']")
      expect(row).to have_css("form[hidden][action='#{article_bookmark_path(article, from: "saved")}'][data-swipe-target='form']", visible: :all)
      expect(row).to have_no_css("[data-swipe-target='saveForm']", visible: :all)
    end

    it "保存が 0 本なら空状態の文言" do
      create(:article)

      get saved_path

      expect(page).to have_css("h1", text: "保存 (0)")
      expect(page).to have_text("まだ保存した記事はありません")
      expect(page).to have_no_css("article")
    end

    it "タブバーの「保存」が現在地で、フィードの未読バッジは保存した記事を数えない" do
      create(:article, :bookmarked)
      create(:article)

      get saved_path

      expect(page).to have_link("保存", href: saved_path)
      expect(page.find_link("保存")["aria-current"]).to eq("page")
      expect(page.find("[data-unread-badge]")).to have_text("1")
    end
  end
end
