RSpec.describe "DailyGoal", type: :request do
  let(:settings) { Dopamine.settings }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:reset_hour) { settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }
  let(:today) { ReadingDay.of(noon) }

  def page
    Capybara.string(response.body)
  end

  def complete(count, at: noon - 1.hour)
    count.times { create(:reading, :completed, opened_at: at) }
  end

  it "未ログインならログイン画面へ" do
    get daily_goal_path
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "達成なら「今日の N 本、読み切った！」、開いた宝箱、ストリーク、今日の合計（本数 ・ 分）、今日のカード（レア・金は色付きのラベル）" do
      complete(goal_articles - 2)
      rare = create(:reading, :completed, :rare, article: create(:article, title: "レアの記事"), opened_at: noon - 30.minutes)
      gold = create(:reading, :completed, :jackpot, article: create(:article, title: "金の記事"), opened_at: noon - 20.minutes)
      create(:daily_goal, :achieved, day: today)

      travel_to(noon) { get daily_goal_path }

      expect(response).to have_http_status(:ok)
      expect(page).to have_text("今日の #{goal_articles} 本、読み切った！")
      expect(page).to have_css("[data-chest=open]")
      expect(page).to have_text("ストリーク 1 日目 確定")
      expect(page).to have_text("#{goal_articles} 本 ・ #{goal_articles * (4 * 60 + 12) / 60} 分")
      expect(page).to have_no_text("XP")
      cards = page.find("ul.card-deck[aria-label='カードの一覧']")
      expect(cards).to have_css("li.card-reveal[data-tier]", count: goal_articles)
      expect(cards).to have_css("li[data-tier='#{rare.tier}'].border-orange-500 [data-rarity-label].bg-orange-500", text: "レア")
      expect(cards).to have_css("li[data-tier='#{rare.tier}'] h3", text: "レアの記事")
      expect(cards).to have_css("li[data-tier='#{gold.tier}'].border-amber-400 [data-rarity-label].bg-amber-400", text: "金")
      expect(cards).to have_css("li[data-tier='#{gold.tier}'] h3", text: "金の記事")
      expect(cards).to have_css("li[data-tier='#{Dopamine.base_rarity[:name]}']", count: goal_articles - 2)
      expect(cards.find("li[data-tier='#{Dopamine.base_rarity[:name]}']", match: :first)).to have_no_css("[data-rarity-label]")
      expect(cards.all("li").map { |li| li["style"][/--i: (\d+)/, 1] }).to eq((0...goal_articles).map(&:to_s))
      expect(cards.first("li")["style"]).to include("--reveal-stagger: #{Dopamine.settings.dig(:cards, :reveal_stagger_ms).to_i}ms")
      expect(cards["data-controller"]).to eq("card-deck") # 履歴で戻ったときにめくり直さない
      expect(page).to have_text("今日のカード #{goal_articles} 枚", normalize_ws: true)
      expect(page).to have_link("今日はここまで", href: root_path)
      expect(page).to have_no_text("レア確率")
    end

    it "達成した日に初めて開いたときだけフィナーレ（蓋が開き、カードが順にめくれ、中身が 1 行ずつ落ち、花火）。2 度目からは開いたまま静か" do
      complete(goal_articles)
      create(:daily_goal, :achieved, day: today)

      travel_to(noon) { get daily_goal_path }
      expect(page).to have_css("[data-finale] svg.chest-finale[data-chest=open]")
      expect(page).to have_css("[data-finale] .fireworks")
      expect(page).to have_css("ul.card-deck li.card-reveal", count: goal_articles)
      expect(page.all("section[aria-label='宝箱の中身'] .finale-drop").map { |row| row["style"][/--i: (\d+)/, 1] }).to eq(%w[0 1 2])
      expect(DailyGoal.find_by(day: today).chest_opened_at).to be_present

      travel_to(noon + 1.minute) { get daily_goal_path }
      expect(page).to have_css("svg[data-chest=open]")
      expect(page).to have_no_css("[data-finale], .chest-finale, .fireworks, .finale-drop, li.card-reveal")
      expect(page).to have_css("ul.card-deck li[data-tier]", count: goal_articles)
      expect(page).to have_text("今日のカード #{goal_articles} 枚", normalize_ws: true)
    end

    it "未達なら開いた記録を残さず、フィナーレも出さない" do
      complete(2)
      goal = create(:daily_goal, day: today)

      travel_to(noon) { get daily_goal_path }
      expect(page).to have_no_css("[data-finale]")
      expect(goal.reload.chest_opened_at).to be_nil
    end

    it "Main のステータス行からの入口は先読みしない（先読みだけでフィナーレを使い切らない）" do
      travel_to(noon) { get root_path }
      expect(page).to have_css("a[href='#{daily_goal_path}'][data-turbo-prefetch='false']")
    end

    it "yml に cards.reveal_stagger_ms があれば、その幅で 1 枚ずつずらしてめくる" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(cards: { reveal_stagger_ms: 120 }))
      complete(goal_articles)
      create(:daily_goal, :achieved, day: today)

      travel_to(noon) { get daily_goal_path }

      expect(page.first("ul.card-deck li")["style"]).to include("--reveal-stagger: 120ms")
    end

    it "ゴール達成ボーナスの行は無い（宝箱の中身はカード。ADR 0020）" do
      complete(goal_articles)
      create(:daily_goal, :achieved, day: today)

      travel_to(noon) { get daily_goal_path }
      expect(page).to have_no_text("ゴール達成ボーナス")
      expect(page).to have_no_text("XP")
    end

    it "昨日も完読していればストリークは続きの日数" do
      complete(1, at: noon - 1.day)
      complete(1, at: noon - 2.days)
      complete(goal_articles)

      travel_to(noon) { get daily_goal_path }

      expect(page).to have_text("ストリーク 3 日目 確定")
    end

    it "一昨日は完読あり、昨日は 0 本なら今日の達成でストリークは 1 日目" do
      complete(1, at: noon - 2.days)
      complete(goal_articles)

      travel_to(noon) { get daily_goal_path }

      expect(page).to have_text("ストリーク 1 日目 確定")
    end

    it "未達なら閉じた宝箱と「あと N 本で宝箱」、「読みに戻る」" do
      complete(2)

      travel_to(noon) { get daily_goal_path }

      expect(page).to have_text("今日のゴール 2 / #{goal_articles}")
      expect(page).to have_css("[data-chest=closed]")
      expect(page).to have_text("あと #{goal_articles - 2} 本で宝箱")
      expect(page).to have_css(".goal-dot[data-filled=true]", count: 2)
      expect(page).to have_link("読みに戻る", href: root_path)
      expect(page).to have_no_text("読み切った")
      expect(page).to have_no_text("ストリーク")
    end

    it "「もう 1 本だけ」は一番新しい未読の「読む」。未読が無ければ出さない" do
      complete(goal_articles)
      create(:article, title: "古い", published_at: noon - 2.days)
      newest = create(:article, title: "新しい", published_at: noon - 1.day)

      travel_to(noon) { get daily_goal_path }
      form = page.find("form[action='#{article_reading_path(newest)}']")
      expect(form).to have_button("もう 1 本だけ")
      expect(page).to have_no_text("ボーナス")
      expect(DailyGoal.count).to eq(0)

      Article.unread.each { |article| create(:reading, :completed, article: article, opened_at: noon - 3.hours) }
      travel_to(noon) { get daily_goal_path }
      expect(page).to have_no_button("もう 1 本だけ")
    end

    it "reset_hour の手前の完読は前日として数え、今日は 0 本" do
      complete(goal_articles, at: Time.zone.local(2026, 10, 20, reset_hour) - 30.minutes)

      travel_to(noon) { get daily_goal_path }

      expect(page).to have_text("今日のゴール 0 / #{goal_articles}")
    end
  end
end
