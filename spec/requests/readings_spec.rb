# 「読む」→ 記事 → 戻る → ReadDone（docs/screens/read_done.md）
RSpec.describe "Readings", type: :request do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:base) { settings.dig(:xp, :base) }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:reset_hour) { settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }
  let(:common) { Dopamine.tier_names.first }

  def page
    Capybara.string(response.body)
  end

  it "未ログインなら読む・戻る・ReadDone はログイン画面へ" do
    article = create(:article)
    post article_reading_path(article)
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    describe "読む（POST /articles/:id/reading）" do
      it "Reading を作って抽選し、記事の URL へ redirect する" do
        article = create(:article, url: "https://example.com/a")
        allow(XpRoulette).to receive(:draw).and_return(common)

        travel_to(noon) { post article_reading_path(article) }

        expect(response).to redirect_to("https://example.com/a")
        reading = article.reload.reading
        expect(reading.tier).to eq(common)
        expect(reading.opened_at).to eq(noon)
        expect(reading.returned_at).to be_nil
      end

      it "未完のまま再び読むと行は 1 つのまま、opened_at を今にして tier は使い回す" do
        article = create(:article)
        reading = create(:reading, article: article, tier: common, opened_at: noon - 1.hour, returned_at: noon - 1.hour + 5.seconds)

        travel_to(noon) { post article_reading_path(article) }

        expect(Reading.count).to eq(1)
        expect(reading.reload.opened_at).to eq(noon)
        expect(reading.returned_at).to be_nil
        expect(reading.tier).to eq(common)
      end

      it "完読済みの記事をもう一度読んでも行は変わらず、記事へ redirect するだけ" do
        article = create(:article, :read)
        before = article.reading.attributes

        post article_reading_path(article)

        expect(response).to redirect_to(article.url)
        expect(article.reading.reload.attributes).to eq(before)
      end
    end

    describe "戻る（POST /readings/:id/return）" do
      it "complete_after_seconds 以上なら完読で XP を確定し、ReadDone へ" do
        reading = create(:reading, tier: common, opened_at: noon)

        travel_to(noon + threshold + 5.seconds) { post return_reading_path(reading) }

        expect(response).to redirect_to(reading_path(reading))
        expect(reading.reload).to be_completed
        expect(reading.xp).to eq(base)
      end

      it "未満なら未完で XP 0" do
        reading = create(:reading, tier: common, opened_at: noon)

        travel_to(noon + threshold - 10.seconds) { post return_reading_path(reading) }

        expect(reading.reload).not_to be_completed
        expect(reading.xp).to eq(0)
      end

      it "2 回目は何も変えない" do
        reading = create(:reading, tier: common, opened_at: noon)
        travel_to(noon + threshold) { post return_reading_path(reading) }
        first = reading.reload.attributes

        travel_to(noon + 1.hour) { post return_reading_path(reading) }

        expect(response).to redirect_to(reading_path(reading))
        expect(reading.reload.attributes).to eq(first)
      end
    end

    describe "ReadDone（GET /readings/:id）" do
      it "完読なら滞在・判定・XP の内訳・3 行要約・ゴール・次の 1 本が出る" do
        article = create(:article, title: "読んだ記事", summary: "・一\n・二\n・三")
        reading = create(:reading, article: article, tier: common, opened_at: noon)
        travel_to(noon + 4.minutes + 12.seconds) { post return_reading_path(reading) }
        create(:article, title: "次の記事", published_at: noon)

        get reading_path(reading)

        expect(response).to have_http_status(:ok)
        expect(page).to have_text("読了！")
        expect(page).to have_text("読んだ記事")
        expect(page).to have_text("滞在 4分12秒")
        expect(page).to have_text("判定 完読")
        expect(page).to have_text(/完読ボーナス\s*\+#{base} XP/)
        expect(page).to have_text(/合計\s*\+#{base} XP/)
        expect(page).to have_text("#{threshold} 秒未満なら XP なし")
        expect(page).to have_text("・一\n・二\n・三")
        expect(page).to have_text(settings.dig(:claude, :summary_model))
        expect(page).to have_text("今日のゴール 1 / #{goal_articles} ・ あと #{goal_articles - 1} 本で宝箱")
        expect(page).to have_css("section[aria-label='次の 1 本']", text: "次の記事")
        expect(page).to have_link("閉じる", href: root_path)
      end

      it "未完なら判定「未完」で合計 +0 XP" do
        reading = create(:reading, tier: common, opened_at: noon)
        travel_to(noon + 5.seconds) { post return_reading_path(reading) }

        get reading_path(reading)

        expect(page).to have_text("判定 未完")
        expect(page).to have_text("合計 +0 XP")
        expect(page).to have_no_text("読了！")
      end

      it "要約が無ければ「要約を準備中」" do
        reading = create(:reading, article: create(:article, :unsummarized), tier: common, opened_at: noon)
        travel_to(noon + threshold) { post return_reading_path(reading) }

        get reading_path(reading)

        expect(response).to have_http_status(:ok)
        expect(page).to have_text("要約を準備中")
      end

      it "今日 N 本目の完読なら「読み切った」、未読 0 なら「全部読んだ」" do
        (goal_articles - 1).times { |i| create(:reading, :completed, opened_at: noon - (i + 1).hours) }
        reading = create(:reading, tier: common, opened_at: noon)
        travel_to(noon + threshold) { post return_reading_path(reading) }

        get reading_path(reading)

        expect(page).to have_text("今日のゴール #{goal_articles} / #{goal_articles}")
        expect(page).to have_text("読み切った")
        expect(page).to have_css("section[aria-label='次の 1 本']", text: "全部読んだ")
      end

      it "まだ戻っていない行の ReadDone は Main へ" do
        reading = create(:reading, tier: common, opened_at: noon)
        get reading_path(reading)
        expect(response).to redirect_to(root_path)
      end
    end

    describe "Main の読了ピルとコンボ" do
      it "開いて戻っていない記事があれば「読了を記録」のピルが出る" do
        article = create(:article, title: "読みかけ")
        reading = create(:reading, article: article, tier: common, opened_at: noon)

        get root_path

        pill = page.find("form[action='#{return_reading_path(reading)}']")
        expect(pill).to have_text("読みかけ")
        expect(pill).to have_button("読了を記録")
        expect(pill["data-controller"]).to eq("reading-return")
      end

      it "戻った記事しか無ければピルは出ない" do
        create(:article, :read)
        get root_path
        expect(page).to have_no_button("読了を記録")
      end

      it "今日 3 本連続完読していればコンボバッジ、無ければ出ない" do
        travel_to noon do
          get root_path
          expect(page).to have_no_text("コンボ ×")

          3.times { |i| create(:reading, :completed, opened_at: noon - (i + 1).hours) }
          get root_path
          step = settings.dig(:xp, :combo_multiplier_step)
          expect(page).to have_text("コンボ ×#{(1 + step * 3).round(1)}")
        end
      end

      it "カードの「読む」は Turbo を切った POST" do
        article = create(:article)
        get root_path
        form = page.find("form[action='#{article_reading_path(article)}']")
        expect(form["data-turbo"]).to eq("false")
        expect(form).to have_button("読む")
      end
    end
  end
end
