# Main（root）。docs/screens/main.md の受け入れ条件のうち、描画で確かめられるもの
RSpec.describe "Main", type: :request do
  let(:goal_articles) { Dopamine.settings.dig(:daily_goal, :articles) }
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }
  # reset_hour から十分離れた「今日」の昼。境界の揺れをテストから外す
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }

  def page
    Capybara.string(response.body)
  end

  it "未ログインなら root はログイン画面へ" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "未読記事が published_at の新しい順に並ぶ" do
      create(:article, title: "古い", published_at: Time.zone.local(2026, 10, 1, 9))
      create(:article, title: "新しい", published_at: Time.zone.local(2026, 10, 3, 9))
      create(:article, title: "中くらい", published_at: Time.zone.local(2026, 10, 2, 9))

      get root_path

      expect(response).to have_http_status(:ok)
      expect(page.all("article h2").map(&:text)).to eq(%w[新しい 中くらい 古い])
    end

    it "カードにフィード名・相対時刻（日本語）・要約（2 行で切る）・「読む」が出る" do
      feed = create(:feed, title: "Ruby Weekly")
      create(:article, feed: feed, title: "記事 A", summary: "・一\n・二\n・三", url: "https://example.com/a", published_at: noon - 3.hours)

      travel_to(noon) { get root_path }

      card = page.find("article")
      expect(card).to have_text("Ruby Weekly")
      expect(card).to have_text("約3時間前")
      expect(card).to have_css("p.line-clamp-2", text: "・一")
      expect(card).to have_button("読む")
    end

    it "興味なしにした記事はカードにも未読数にも出ない。カードには「興味なし」のボタンがある" do
      create(:article, title: "残る記事")
      create(:article, :dismissed, title: "興味なしの記事")

      get root_path

      expect(page).to have_css("article h2", text: "残る記事")
      expect(page).to have_no_text("興味なしの記事")
      expect(page).to have_text("未読 1 件")
      expect(page.find("article")).to have_button("興味なし")
    end

    it "published_at が無い記事は相対時刻を出さない" do
      create(:article, title: "日付なし", published_at: nil)

      get root_path

      card = page.find("article")
      expect(card).to have_css("h2", text: "日付なし")
      expect(card).to have_no_css("time")
    end

    it "要約が無い記事は見出しだけで、要約欄が無い" do
      create(:article, :unsummarized, title: "要約前")

      get root_path

      card = page.find("article")
      expect(card).to have_css("h2", text: "要約前")
      expect(card).to have_no_css("p.line-clamp-2")
    end

    it "完読した記事はカードに出ず、開いただけの記事は出る" do
      create(:article, :read, title: "読んだ")
      create(:article, :opened, title: "開いただけ")

      get root_path

      expect(page).to have_no_css("article h2", text: "読んだ")
      expect(page).to have_css("article h2", text: "開いただけ")
    end

    it "今日 3 本読了なら「今日のゴール 3 / N」でドットが 3 個塗られる" do
      travel_to noon do
        3.times { create(:reading, :completed, opened_at: noon - 1.hour) }
        create(:reading, :completed, opened_at: noon - 2.days)

        get root_path

        expect(page).to have_text("今日のゴール 3 / #{goal_articles}")
        expect(page).to have_css(".goal-dot", count: goal_articles)
        expect(page).to have_css(".goal-dot[data-filled=true]", count: 3)
      end
    end

    it "今日 0 本なら「今日のゴール 0 / N」で全ドットが灰色" do
      travel_to noon do
        get root_path

        expect(page).to have_text("今日のゴール 0 / #{goal_articles}")
        expect(page).to have_no_css(".goal-dot[data-filled=true]")
      end
    end

    it "ストリーク・未読数・読了累計・累計 XP が出る" do
      travel_to noon do
        3.times { |i| create(:reading, :completed, opened_at: noon - (i + 1).days, xp: 10) }
        2.times { create(:article) }

        get root_path

        expect(page).to have_text("3日連続")
        expect(page).to have_text("未読 2 件")
        expect(page).to have_text("読了 3")
        expect(page).to have_text("累計 30 XP")
      end
    end

    it "未読が 48 本ならタブバーのフィードに「48」バッジ" do
      48.times { create(:article) }

      get root_path

      expect(page.find("nav[aria-label='タブバー']")).to have_css("[data-unread-badge]", text: "48")
    end

    it "未読が 0 本ならバッジが出ず「全部読んだ」の空状態" do
      create(:article, :read)

      get root_path

      expect(page.find("nav[aria-label='タブバー']")).to have_no_css("[data-unread-badge]")
      expect(page).to have_text("全部読んだ。")
      expect(page).to have_text("次の記事が届くまで、今日はここまで。")
      expect(page).to have_no_css("article")
    end

    it "フィード以外のタブは無効で、フィードが現在地" do
      get root_path

      nav = page.find("nav[aria-label='タブバー']")
      expect(nav).to have_css("[aria-current=page]", text: "フィード")
      expect(nav).to have_css("[aria-disabled=true]", count: 3)
    end

    it "今日のゴールの行は DailyGoal へのリンク" do
      get root_path

      expect(page).to have_link(href: daily_goal_path, text: /今日のゴール 0 \/ #{goal_articles}/)
    end

    it "累計 XP には宝箱のボーナスも乗る" do
      travel_to noon do
        create(:reading, :completed, opened_at: noon - 1.hour, xp: 30)
        create(:daily_goal, :achieved, day: ReadingDay.of(noon) - 1, bonus_xp: 100)

        get root_path

        expect(page).to have_text("累計 130 XP")
      end
    end

    it "設定ボタンから Learning へ" do
      get root_path

      expect(page).to have_link("設定", href: learning_path)
    end
  end
end
