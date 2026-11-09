RSpec.describe "DailyGoal", type: :request do
  let(:settings) { Dopamine.settings }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:reset_hour) { settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }
  let(:today) { ReadingDay.of(noon) }

  def page
    Capybara.string(response.body)
  end

  def complete(count, at: noon - 1.hour, xp: 10)
    count.times { create(:reading, :completed, opened_at: at, xp: xp) }
  end

  it "未ログインならログイン画面へ" do
    get daily_goal_path
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "達成なら「今日の N 本、読み切った！」、開いた宝箱、ストリーク、今日の合計（本数 ・ 分 ・ XP）" do
      complete(goal_articles, xp: 62)
      create(:daily_goal, :achieved, day: today)

      travel_to(noon) { get daily_goal_path }

      expect(response).to have_http_status(:ok)
      expect(page).to have_text("今日の #{goal_articles} 本、読み切った！")
      expect(page).to have_css("[data-chest=open]")
      expect(page).to have_text("ストリーク 1 日目 確定")
      expect(page).to have_text("#{goal_articles} 本 ・ #{goal_articles * (4 * 60 + 12) / 60} 分 ・ #{goal_articles * 62} XP")
      expect(page).to have_link("今日はここまで", href: root_path)
      expect(page).to have_no_text("レア確率")
    end

    it "ゴール達成ボーナスの行は bonus_xp があるときだけ" do
      complete(goal_articles)
      goal = create(:daily_goal, :achieved, day: today)

      travel_to(noon) { get daily_goal_path }
      expect(page).to have_no_text("ゴール達成ボーナス")

      goal.update!(bonus_xp: 100)
      travel_to(noon) { get daily_goal_path }
      expect(page).to have_text("ゴール達成ボーナス")
      expect(page).to have_text("+100 XP")
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
      expect(page).to have_no_text("ボーナス XP は半分")
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
