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

  it "未ログインなら読む・戻る・ReadDone・Jackpot はログイン画面へ" do
    article = create(:article)
    post article_reading_path(article)
    expect(response).to redirect_to(new_session_path)

    get jackpot_reading_path(create(:reading, tier: Dopamine.jackpot_tier[:name]))
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

      it "開いたまま戻っていない記事をもう一度読むと opened_at を今にする" do
        article = create(:article)
        reading = create(:reading, article: article, tier: common, opened_at: noon - 1.hour)

        travel_to(noon) { post article_reading_path(article) }

        expect(reading.reload.opened_at).to eq(noon)
        expect(reading.returned_at).to be_nil
      end

      it "無い記事なら 404" do
        post article_reading_path(0)
        expect(response).to have_http_status(:not_found)
      end

      it "完読済みの記事をもう一度読んでも行は変わらず、記事へ redirect するだけ" do
        article = create(:article, :read)
        before = article.reading.attributes

        post article_reading_path(article)

        expect(response).to redirect_to(article.url)
        expect(article.reading.reload.attributes).to eq(before)
      end
    end

    describe "Roulette（Turbo の POST /articles/:id/reading）" do
      let(:tiers) { settings.dig(:xp, :tiers) }
      let(:duration) { settings.dig(:xp, :roulette_duration_ms) }
      let(:jackpot) { Dopamine.jackpot_tier }
      let(:rare) { tiers.find { |tier| tier[:multiplier] > 1 && tier != jackpot } }

      def post_turbo(article)
        post article_reading_path(article), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
      end

      # turbo-stream の中身は <template> に包まれ、HTML4 の parser は template の子を捨てるので外して読む
      def page
        Capybara.string(response.body.gsub(%r{</?template>}, ""))
      end

      it "モーダルを #roulette に差し込む。出目の帯・出目表・長さは yml から組み、止まったら記事へのリンクを持つ" do
        article = create(:article, url: "https://example.com/a")
        allow(XpRoulette).to receive(:draw).and_return(common)

        travel_to(noon) { post_turbo(article) }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(page).to have_css("turbo-stream[action='update'][target='roulette']")
        expect(page).to have_css("[data-controller='roulette'][data-roulette-duration-value='#{duration}'][data-tier='#{common}']")
        expect(page).to have_text("「読む」を押した #{duration / 1000.0} 秒間")
        tiers.each do |tier|
          xp = base * tier[:multiplier]
          expect(page).to have_css(".roulette-strip li[data-tier='#{tier[:name]}']", text: "+#{xp} XP", minimum: 2)
          expect(page).to have_css("table tr[data-tier='#{tier[:name]}']", text: /#{(tier[:probability] * 100).round}%.*×#{tier[:multiplier]}.*\+#{xp} XP/m)
        end
        expect(page).to have_css("table tr[data-tier='#{common}'][data-selected]")
        expect(page).to have_css("table tr[data-selected]", count: 1)
        link = page.find_link("記事を開く", href: "https://example.com/a")
        expect(link["data-turbo"]).to eq("false")
        expect(link["data-action"]).to eq("click->reading-return#opened")
        expect(page).to have_no_text("ボーナス ×")
        expect(article.reload.reading.opened_at).to eq(noon)
      end

      it "rare なら「掘り出し物ボーナス ×K → 合計 +M XP」が出る（K・M は yml）" do
        allow(XpRoulette).to receive(:draw).and_return(rare[:name])

        post_turbo(create(:article))

        expect(page).to have_text("掘り出し物ボーナス ×#{rare[:multiplier]} → 合計 +#{base * rare[:multiplier]} XP")
        expect(page).to have_css("table tr[data-tier='#{rare[:name]}'][data-selected]")
      end

      it "jackpot ならリンク先は Jackpot 画面で、記事へは直接出ない" do
        allow(XpRoulette).to receive(:draw).and_return(jackpot[:name])
        article = create(:article)

        post_turbo(article)

        link = page.find_link("ジャックポットへ", href: jackpot_reading_path(article.reload.reading))
        expect(link["data-turbo"]).to be_nil
        expect(link["data-action"]).to be_nil
        expect(page).to have_no_link("記事を開く")
      end

      it "未完のまま再び読むと再抽選せず、前回の出目で止まる" do
        article = create(:article)
        create(:reading, article: article, tier: rare[:name], opened_at: noon - 1.hour, returned_at: noon - 1.hour + 5.seconds)
        expect(XpRoulette).not_to receive(:draw)

        post_turbo(article)

        expect(page).to have_css("[data-controller='roulette'][data-tier='#{rare[:name]}']")
        expect(Reading.count).to eq(1)
      end

      it "通常の POST（JS 無し）は今までどおり記事へ redirect" do
        article = create(:article, url: "https://example.com/a")
        allow(XpRoulette).to receive(:draw).and_return(common)

        post article_reading_path(article)

        expect(response).to redirect_to("https://example.com/a")
      end
    end

    describe "Jackpot（GET /readings/:id/jackpot）" do
      let(:jackpot) { Dopamine.jackpot_tier }

      it "全画面に JACKPOT・XP（base × multiplier）・確率・記事・「受け取って読む」。閉じるは無い" do
        article = create(:article, title: "当たり記事", url: "https://example.com/j", feed: create(:feed, title: "Ruby Weekly"))
        reading = create(:reading, article: article, tier: jackpot[:name], opened_at: noon)

        get jackpot_reading_path(reading)

        expect(response).to have_http_status(:ok)
        expect(page).to have_css("[role='dialog'][aria-label='ジャックポット']", text: "JACKPOT")
        expect(page).to have_text("+#{base * jackpot[:multiplier]}")
        expect(page).to have_text("XP ・ 通常 #{base} の #{jackpot[:multiplier]} 倍")
        expect(page).to have_text("#{(jackpot[:probability] * 100).round}% のジャックポット")
        expect(page).to have_text("Ruby Weekly")
        expect(page).to have_text("当たり記事")
        button = page.find_link("受け取って読む", href: "https://example.com/j")
        expect(button["data-turbo"]).to eq("false")
        expect(button["data-action"]).to eq("click->reading-return#opened")
        expect(page).to have_css("form.hidden[action='#{return_readings_path}'][data-reading-return-target='form']", visible: :all)
        expect(page).to have_no_link("閉じる")
        expect(page).to have_no_button("閉じる")
      end

      it "完読済みでも開ける（戻るで Main に帰っても結果は保持され、再び読めば同じ画面）" do
        reading = create(:reading, :completed, tier: jackpot[:name], opened_at: noon)
        get jackpot_reading_path(reading)
        expect(response).to have_http_status(:ok)
        expect(page).to have_text("JACKPOT")
      end

      it "jackpot でない行なら Main へ" do
        reading = create(:reading, tier: common, opened_at: noon)
        get jackpot_reading_path(reading)
        expect(response).to redirect_to(root_path)
      end

      it "無い行なら 404" do
        get jackpot_reading_path(0)
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "戻る（POST /readings/return）" do
      it "complete_after_seconds 以上なら完読で XP を確定し、ReadDone へ" do
        reading = create(:reading, tier: common, opened_at: noon)

        travel_to(noon + threshold + 5.seconds) { post return_readings_path }

        expect(response).to redirect_to(reading_path(reading))
        expect(reading.reload).to be_completed
        expect(reading.xp).to eq(base)
      end

      it "未満なら未完で XP 0" do
        reading = create(:reading, tier: common, opened_at: noon)

        travel_to(noon + threshold - 10.seconds) { post return_readings_path }

        expect(reading.reload).not_to be_completed
        expect(reading.xp).to eq(0)
      end

      it "開いた行が無ければ Main へ戻すだけ" do
        create(:article, :read)
        post return_readings_path
        expect(response).to redirect_to(root_path)
      end

      it "開いたまま戻っていない行が複数あれば最新だけを閉じる" do
        older = create(:reading, tier: common, opened_at: noon - 1.hour)
        newer = create(:reading, tier: common, opened_at: noon)

        travel_to(noon + threshold) { post return_readings_path }

        expect(response).to redirect_to(reading_path(newer))
        expect(newer.reload.returned_at).to be_present
        expect(older.reload.returned_at).to be_nil
      end

      it "閉じた後にもう一度送っても行は変わらず Main へ" do
        reading = create(:reading, tier: common, opened_at: noon)
        travel_to(noon + threshold) { post return_readings_path }
        first = reading.reload.attributes

        travel_to(noon + 1.hour) { post return_readings_path }

        expect(response).to redirect_to(root_path)
        expect(reading.reload.attributes).to eq(first)
      end
    end

    describe "ReadDone（GET /readings/:id）" do
      it "完読なら滞在・判定・XP の内訳・3 行要約・ゴール・次の 1 本が出る" do
        article = create(:article, title: "読んだ記事", summary: "・一\n・二\n・三")
        reading = create(:reading, article: article, tier: common, opened_at: noon)
        travel_to(noon + 4.minutes + 12.seconds) { post return_readings_path }
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

      it "コンボが付いていれば内訳に「コンボ ×C +B XP」の行が出て、合計は完読ボーナス × C" do
        rare = Dopamine.tier_names.second
        step = settings.dig(:xp, :combo_multiplier_step)
        2.times { |i| create(:reading, :completed, opened_at: noon - (i + 1).hours, returned_at: noon - (i + 1).hours + 5.minutes, completed_at: noon - (i + 1).hours + 5.minutes) }
        reading = create(:reading, tier: rare, opened_at: noon)
        travel_to(noon + threshold) { post return_readings_path }

        get reading_path(reading)

        multiplier = (1 + step * 2).round(1)
        bonus = base * Dopamine.tier(rare)[:multiplier]
        expect(page).to have_text("3 本連続 ・ コンボ ×#{multiplier}")
        expect(page).to have_text(/完読ボーナス\s*\+#{bonus} XP/)
        expect(page).to have_text(/コンボ ×#{multiplier}\s*\+#{(bonus * multiplier).round - bonus} XP/)
        expect(page).to have_text(/合計\s*\+#{(bonus * multiplier).round} XP/)
      end

      it "未完なら判定「未完」で合計 +0 XP" do
        reading = create(:reading, tier: common, opened_at: noon)
        travel_to(noon + 5.seconds) { post return_readings_path }

        get reading_path(reading)

        expect(page).to have_text("判定 未完")
        expect(page).to have_text("合計 +0 XP")
        expect(page).to have_no_text("読了！")
      end

      it "要約が無ければ「要約を準備中」" do
        reading = create(:reading, article: create(:article, :unsummarized), tier: common, opened_at: noon)
        travel_to(noon + threshold) { post return_readings_path }

        get reading_path(reading)

        expect(response).to have_http_status(:ok)
        expect(page).to have_text("要約を準備中")
      end

      it "今日 N 本目の完読なら「読み切った」、未読 0 なら「全部読んだ」" do
        (goal_articles - 1).times { |i| create(:reading, :completed, opened_at: noon - (i + 1).hours) }
        reading = create(:reading, tier: common, opened_at: noon)
        travel_to(noon + threshold) { post return_readings_path }

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

        pill = page.find("form[action='#{return_readings_path}']:not(.hidden)")
        expect(pill).to have_text("読みかけ")
        expect(pill).to have_button("読了を記録")
        expect(pill["data-action"]).to eq("submit->reading-return#returned")
        expect(reading.reload.returned_at).to be_nil
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

      it "カードの「読む」は Turbo の POST（モーダルを受ける）。記事へ出る印は submit ではなくモーダルのリンクが付ける" do
        article = create(:article)
        get root_path
        form = page.find("form[action='#{article_reading_path(article)}']")
        expect(form["data-turbo"]).to be_nil
        expect(form["data-action"]).to be_nil
        expect(form).to have_button("読む")
        expect(page).to have_css("main[data-controller='reading-return'] #roulette")
      end

      it "Main と ReadDone は画面全体を reading-return が包み、戻りの合図で送る隠し form を持つ" do
        reading = create(:reading, :completed)
        [ root_path, reading_path(reading) ].each do |path|
          get path
          expect(page).to have_css("main[data-controller='reading-return']")
          expect(page).to have_css("form.hidden[action='#{return_readings_path}'][data-reading-return-target='form']", visible: :all)
        end
      end
    end
  end
end
