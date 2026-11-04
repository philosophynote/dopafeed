# アプリ内のリーダー（docs/screens/reader.md）。本文の描画と、末尾の「読み終えた」form まで
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

    it "本文・出目の帯・元記事へのリンク・末尾の「読み終えた」form を出す" do
      rare = settings.dig(:xp, :tiers).find { |tier| tier[:multiplier] > 1 && tier != Dopamine.jackpot_tier }
      article = create(:article, title: "読む記事", url: "https://example.com/posts/1", feed: create(:feed, title: "Ruby Weekly"),
                                 content: "<h2>見出し</h2><p>本文の段落。</p>", content_fetched_at: noon)
      reading = create(:reading, article: article, tier: rare[:name], opened_at: noon)

      get read_article_path(article)

      expect(response).to have_http_status(:ok)
      reader = page.find("#reader")
      expect(reader).to have_css("h1", text: "読む記事")
      expect(reader).to have_text("Ruby Weekly")
      expect(reader).to have_text("出目 掘り出し物 ×#{rare[:multiplier]} ・ 完読で +#{base * rare[:multiplier]} XP")
      expect(reader).to have_css(".reader-body h2", text: "見出し")
      expect(reader).to have_css(".reader-body p", text: "本文の段落。")
      expect(reader).to have_link("元記事で読む", href: "https://example.com/posts/1")
      form = reader.find("form#end_reading_#{reading.id}[action='#{advance_reading_path(reading)}'][data-controller='reader']")
      expect(form).to have_button("読み終えた")
      expect(page).to have_link("閉じる", href: root_path)
    end

    it "本文は許したタグと属性だけ残し、相対 URL は記事の URL で解決し、リンクは別タブで開く" do
      content = <<~HTML
        <script>alert(1)</script>
        <p onclick="steal()" style="color:red">段落<a href="javascript:alert(1)">悪いリンク</a><a href="/about">相対リンク</a></p>
        <img src="images/a.png" onerror="steal()">
        <iframe src="https://evil.example.com"></iframe>
      HTML
      article = create(:article, url: "https://example.com/posts/1", content: content, content_fetched_at: noon)
      create(:reading, article: article, opened_at: noon)

      get read_article_path(article)

      body = page.find(".reader-body")
      expect(response.body).not_to include("alert(1)</script>")
      expect(body).to have_no_css("script, iframe, [onclick], [style], [onerror]", visible: :all)
      expect(body).to have_no_css("a[href^='javascript']", visible: :all)
      expect(body).to have_css("a[href='https://example.com/about'][target='_blank'][rel='noopener noreferrer']", text: "相対リンク")
      expect(body).to have_css("img[src='https://example.com/posts/images/a.png'][loading='lazy']", visible: :all)
    end

    it "本文を取れなかった記事は要約と元記事へのリンクで代わりにする" do
      article = create(:article, summary: "・一\n・二\n・三", content: "<p>抜粋</p>", content_fetched_at: noon, content_error: "HTTP 404")
      create(:reading, article: article, opened_at: noon)

      get read_article_path(article)

      expect(page).to have_no_css(".reader-body")
      expect(page).to have_text("本文を取れなかった")
      expect(page).to have_text("・一\n・二\n・三")
      expect(page).to have_link("元記事で読む", href: article.url)
      expect(page).to have_button("読み終えた")
    end

    it "要約も無ければ「要約を準備中」" do
      article = create(:article, :unsummarized)
      create(:reading, article: article, opened_at: noon)

      get read_article_path(article)

      expect(page).to have_text("要約を準備中")
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
