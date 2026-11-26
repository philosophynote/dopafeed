RSpec.describe "Articles", type: :request do
  let(:settings) { Dopamine.settings }
  let(:noon) { Time.zone.local(2026, 10, 20, 12) }

  def page
    Capybara.string(response.body)
  end

  it "未ログインならログイン画面へ" do
    get read_article_path(create(:article, :opened))
    expect(response).to redirect_to(new_session_path)

    get summary_article_path(create(:article, :opened))
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "判定済みの区切りを描き直しても「宝箱を開く」は今日の goal 本目にだけ出る（後から読み足しても、前の日でも変わらない）" do
      goal_articles = settings.dig(:daily_goal, :articles)
      readings = (goal_articles + 1).times.map { |i| create(:reading, :completed, opened_at: noon - 3.hours + i.minutes) }
      yesterday = create(:reading, :completed, opened_at: noon - 1.day)

      travel_to(noon) { get read_article_path(readings[goal_articles - 1].article) }
      expect(page).to have_link("宝箱を開く", href: daily_goal_path)

      travel_to(noon) { get read_article_path(readings[goal_articles - 2].article) }
      expect(page).to have_no_link("宝箱を開く")

      travel_to(noon) { get read_article_path(readings[goal_articles].article) }
      expect(page).to have_no_link("宝箱を開く")

      travel_to(noon) { get read_article_path(yesterday.article) }
      expect(page).to have_no_link("宝箱を開く")
    end

    it "見出し・枠の帯・要約・元サイトを別窓で開く「記事を開く」・「読み終えた」form を出す" do
      rare = Dopamine.rarity(Dopamine.rarity_names.second)
      article = create(:article, title: "読む記事", url: "https://example.com/posts/1", feed: create(:feed, title: "Ruby Weekly"),
                                 summary: "・一\n・二\n・三")
      reading = create(:reading, article: article, tier: rare[:name], opened_at: noon)

      get read_article_path(article)

      expect(response).to have_http_status(:ok)
      reader = page.find("#reader")
      card = reader.find("[data-controller='sheet'][data-sheet-start-url-value='#{start_reading_path(reading)}']")
      expect(card).to have_css("h1", text: "読む記事")
      expect(card).to have_text("Ruby Weekly")
      expect(card).to have_text("レア ・ 完読でレアカード")
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

    it "判定が済んだ記事は form の代わりに結果を出す（再読込で二度送らない）" do
      reading = create(:reading, :completed, opened_at: noon)

      get read_article_path(reading.article)

      expect(page).to have_no_button("読み終えた")
      expect(page).to have_css("section[aria-label='判定']", text: "カードを手に入れた！")
    end

    it "判定済みの区切りを描き直すときはカードを表のまま出し、めくり直さず全画面も出さない" do
      reading = create(:reading, :completed, :jackpot, article: create(:article, title: "前に読んだ金"), opened_at: noon)

      get read_article_path(reading.article)

      expect(page).to have_css("section[aria-label='判定'] li[data-tier='#{reading.tier}'] h3", text: "前に読んだ金")
      expect(page).to have_no_css("li.card-reveal")
      expect(page).to have_no_css("[role='dialog']")
    end

    it "「読む」を押していない記事は Main へ" do
      get read_article_path(create(:article))
      expect(response).to redirect_to(root_path)
    end

    it "無い記事なら 404" do
      get read_article_path(0)
      expect(response).to have_http_status(:not_found)
    end

    describe "Reader の要約欄" do
      let(:article) { create(:article, :awaiting_summary, :opened) }

      def subscribed?
        page.has_css?("[data-controller='pending-refresh'][data-pending-refresh-url-value='#{summary_article_path(article)}'] turbo-cable-stream-source")
      end

      it "要約が無い間は「要約を作成中」を出し、できたら差し替わるよう購読する" do
        get read_article_path(article)

        expect(page).to have_css("turbo-frame#summary_article_#{article.id}", text: "要約を作成中")
        expect(subscribed?).to be(true)
      end

      it "開くたびに要約待ちなら Job を積み直す（予算切れで捨てた翌日に開き直したとき）" do
        get read_article_path(article)

        expect(Claude::SummarizeArticleJob).to have_been_enqueued.with(article)
      end

      it "本文取得がまだの記事も「作成中」で待つ（Job は本文取得の後に積まれる）" do
        article.update!(content_fetched_at: nil)

        get read_article_path(article)

        expect(page).to have_css("turbo-frame#summary_article_#{article.id}", text: "要約を作成中")
        expect(subscribed?).to be(true)
        expect(Claude::SummarizeArticleJob).not_to have_been_enqueued
      end

      it "要約があれば出し、購読しない" do
        article.update!(summary: "・一\n・二\n・三")

        get read_article_path(article)

        expect(page).to have_css("turbo-frame#summary_article_#{article.id}", text: "・一")
        expect(subscribed?).to be(false)
        expect(Claude::SummarizeArticleJob).not_to have_been_enqueued
      end

      it "失敗した記事は「要約できませんでした」。記事を開くのはそのまま" do
        article.update!(summary_failed_at: Time.current, summary_error: "本文が空")

        get read_article_path(article)

        expect(page).to have_css("turbo-frame#summary_article_#{article.id}", text: "要約できませんでした")
        expect(page).to have_link("記事を開く", href: article.url)
        expect(subscribed?).to be(false)
      end

      it "今日の上限に達していれば「今日の要約の上限に達しました」" do
        allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))

        get read_article_path(article)

        expect(page).to have_css("turbo-frame#summary_article_#{article.id}", text: "今日の要約の上限に達しました")
        expect(page).to have_link("記事を開く", href: article.url)
        expect(subscribed?).to be(true)
      end

      it "GET /articles/:id/summary は要約欄の frame だけを描く（購読がつながる前に書き終えた分の取り直し）" do
        article.update!(summary: "・一\n・二\n・三")

        get summary_article_path(article)

        expect(response).to have_http_status(:ok)
        expect(page).to have_css("turbo-frame#summary_article_#{article.id}", text: "・一")
        expect(page).to have_no_css("h1")
      end

      it "summary は書き込まない（Job も積まない）" do
        get summary_article_path(article)

        expect(Claude::SummarizeArticleJob).not_to have_been_enqueued
      end

      it "summary は無い記事なら 404" do
        get summary_article_path(0)
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "Reader のコメント欄" do
      let(:comments) { { personas_shown: 3, model: "grok-4.3", max_tokens: 4000, timeout_seconds: 60, stream_interval_ms: 250 } }
      let(:article) { create(:article, :bookmarked, :opened, summary: "・一\n・二\n・三") }

      before do
        seed_personas
        allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(comments: comments))
      end

      def card
        page.find("#reader [data-controller='sheet']")
      end

      it "要約の下、「記事を開く」の上に「? ? ?」と「コメントを見る」の欄を出す" do
        get read_article_path(article)

        box = card.find("##{ActionView::RecordIdentifier.dom_id(article, :comments_box)} section[aria-label='コメント']")
        expect(box).to have_text("? ? ?")
        expect(box).to have_button("コメントを見る")
        expect(box.find("form")[:action]).to eq(article_comments_path(article))
        expect(box).to have_text("人物は AI による架空のキャラクターです。本人の発言ではありません")
        order = card.all("turbo-frame#summary_article_#{article.id}, section[aria-label='コメント'], a[data-action='sheet#open']")
        expect(order.map { |node| node[:id] || node[:"aria-label"] || node.text }).to eq([ "summary_article_#{article.id}", "コメント", "記事を開く" ])
      end

      it "作成済みの記事は、その組のカードと「別の 3 人を見る」を出す" do
        Persona.enabled.first(3).each { |persona| article.persona_comments.create!(persona_id: persona.slug, body: "#{persona.name}のひとこと") }

        get read_article_path(article)

        expect(card).to have_css("section[aria-label='コメント'] [data-persona-id]", count: 3)
        expect(card).to have_text("#{Persona.enabled.first.name}のひとこと")
        expect(card).to have_button("別の 3 人を見る")
      end

      it "鍵が欠けていれば欄を出さない" do
        comments.delete(:model)

        get read_article_path(article)

        expect(page).to have_no_css("section[aria-label='コメント']")
      end

      it "有効な人物が 0 人なら欄を出さない" do
        Persona.update_all(enabled: false)

        get read_article_path(article)

        expect(page).to have_no_css("section[aria-label='コメント']")
      end
    end
  end
end
