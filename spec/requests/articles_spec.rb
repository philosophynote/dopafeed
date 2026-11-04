# Reader（docs/screens/reader.md）のカード。本文は描かず、要約と元サイトを開くリンク、開いた後の「読み終えた」form まで
RSpec.describe "Articles", type: :request do
  let(:settings) { Dopamine.settings }
  let(:base) { settings.dig(:xp, :base) }
  let(:noon) { Time.zone.local(2026, 10, 20, 12) }

  def page
    Capybara.string(response.body)
  end

  it "未ログインならログイン画面へ" do
    get read_article_path(create(:article, :opened))
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "見出し・出目の帯・要約・元サイトを別窓で開く「記事を開く」・「読み終えた」form を出す" do
      rare = settings.dig(:xp, :tiers).find { |tier| tier[:multiplier] > 1 && tier != Dopamine.jackpot_tier }
      article = create(:article, title: "読む記事", url: "https://example.com/posts/1", feed: create(:feed, title: "Ruby Weekly"),
                                 summary: "・一\n・二\n・三")
      reading = create(:reading, article: article, tier: rare[:name], opened_at: noon)

      get read_article_path(article)

      expect(response).to have_http_status(:ok)
      reader = page.find("#reader")
      card = reader.find("[data-controller='sheet'][data-sheet-start-url-value='#{start_reading_path(reading)}']")
      expect(card).to have_css("h1", text: "読む記事")
      expect(card).to have_text("Ruby Weekly")
      expect(card).to have_text("出目 掘り出し物 ×#{rare[:multiplier]} ・ 完読で +#{base * rare[:multiplier]} XP")
      expect(card).to have_text("・一\n・二\n・三")
      expect(card).to have_css("a[href='https://example.com/posts/1'][target='_blank'][rel='noopener noreferrer'][data-action='sheet#open']",
                               text: "記事を開く")
      form = card.find("form#end_reading_#{reading.id}[action='#{advance_reading_path(reading)}'][data-sheet-target='finish']")
      expect(form).to have_button("読み終えた")
      expect(page).to have_link("閉じる", href: root_path)
    end

    it "取得した本文はアプリ内に描かない（元サイトの見た目のまま読む）" do
      article = create(:article, content: "<h2>本文の見出し</h2><p>本文の段落。</p>", content_fetched_at: noon, summary: "・要約")
      create(:reading, article: article, opened_at: noon)

      get read_article_path(article)

      expect(response.body).not_to include("本文の段落。")
      expect(page).to have_no_css("h2", text: "本文の見出し")
      expect(page).to have_text("・要約")
    end

    it "要約がまだ無ければ「要約を準備中」" do
      article = create(:article, :unsummarized)
      create(:reading, article: article, opened_at: noon)

      get read_article_path(article)

      expect(page).to have_text("要約を準備中")
      expect(page).to have_link("記事を開く", href: article.url)
    end

    it "判定が済んだ記事は form の代わりに結果を出す（再読込で二度送らない）" do
      reading = create(:reading, :completed, opened_at: noon)

      get read_article_path(reading.article)

      expect(page).to have_no_button("読み終えた")
      expect(page).to have_css("section[aria-label='判定']", text: "読了！")
    end

    it "「読む」を押していない記事は Main へ" do
      get read_article_path(create(:article))
      expect(response).to redirect_to(root_path)
    end

    it "無い記事なら 404" do
      get read_article_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
