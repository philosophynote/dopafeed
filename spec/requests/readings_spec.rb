# 「読む」→ Roulette / Jackpot → Reader で記事を開いて読み終える → 判定と次の記事（docs/screens/reader.md・roulette.md・jackpot.md）
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

  it "未ログインなら読む・Jackpot はログイン画面へ" do
    article = create(:article)
    post article_reading_path(article)
    expect(response).to redirect_to(new_session_path)

    get jackpot_reading_path(create(:reading, tier: Dopamine.jackpot_tier[:name]))
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    describe "読む（POST /articles/:id/reading）" do
      it "Reading を作って抽選し、アプリ内のリーダーへ redirect する" do
        article = create(:article, url: "https://example.com/a")
        allow(XpRoulette).to receive(:draw).and_return(common)

        travel_to(noon) { post article_reading_path(article) }

        expect(response).to redirect_to(read_article_path(article))
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

      it "開いたまま判定前の記事をもう一度読むと opened_at を今にする" do
        article = create(:article)
        reading = create(:reading, article: article, tier: common, opened_at: noon - 1.hour)

        travel_to(noon) { post article_reading_path(article) }

        expect(reading.reload.opened_at).to eq(noon)
        expect(reading.returned_at).to be_nil
      end

      it "要約待ちの記事なら要約の Job を積む（要約は読むと決めた記事だけ。ADR 0015）" do
        article = create(:article, :awaiting_summary)

        post article_reading_path(article)

        expect(Claude::SummarizeArticleJob).to have_been_enqueued.with(article).once
      end

      it "要約済み・失敗済み・本文取得前の記事では積まない（一度作った要約は使い回す）" do
        [ create(:article), create(:article, :summary_failed), create(:article, :unsummarized) ].each { |article| post article_reading_path(article) }

        expect(Claude::SummarizeArticleJob).not_to have_been_enqueued
      end

      it "要約済みの記事を開き直しても積まない" do
        article = create(:article, :opened)

        post article_reading_path(article)

        expect(Claude::SummarizeArticleJob).not_to have_been_enqueued
      end

      it "無い記事なら 404" do
        post article_reading_path(0)
        expect(response).to have_http_status(:not_found)
      end

      it "完読済みの記事をもう一度読んでも行は変わらず、リーダーへ redirect するだけ" do
        article = create(:article, :read)
        before = article.reading.attributes

        post article_reading_path(article)

        expect(response).to redirect_to(read_article_path(article))
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

      it "モーダルを #roulette に差し込む。出目の帯・出目表・長さは yml から組み、止まったらリーダーへのリンクを持つ" do
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
        link = page.find_link("記事を開く", href: read_article_path(article))
        expect(link["data-turbo"]).to be_nil
        expect(link["data-action"]).to be_nil
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

      # 二重タップで同じ記事の行が同時に作られた: 読み込み時は行が無く、INSERT が一意制約で落ちる
      def race_on(article, existing_tier:)
        create(:reading, article: article, tier: existing_tier, opened_at: noon - 1.hour)
        ghost = Reading.new(article: article)
        allow(Reading).to receive(:find_or_initialize_by).and_return(ghost)
        allow(ghost).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new("二重タップ"))
      end

      it "二重タップで行が同時に作られたら、先に入った行の出目でモーダルを返す" do
        article = create(:article)
        race_on(article, existing_tier: rare[:name])

        post_turbo(article)

        expect(response).to have_http_status(:ok)
        expect(page).to have_css("[data-controller='roulette'][data-tier='#{rare[:name]}']")
        expect(Reading.count).to eq(1)
      end

      it "二重タップの JS 無し経路も先に入った行を使ってリーダーへ redirect" do
        article = create(:article, url: "https://example.com/a")
        race_on(article, existing_tier: common)

        post article_reading_path(article)

        expect(response).to redirect_to(read_article_path(article))
        expect(Reading.count).to eq(1)
      end

      it "通常の POST（JS 無し）は演出なしでリーダーへ redirect" do
        article = create(:article, url: "https://example.com/a")
        allow(XpRoulette).to receive(:draw).and_return(common)

        post article_reading_path(article)

        expect(response).to redirect_to(read_article_path(article))
      end
    end

    describe "行を広げる（Main の行からの Turbo の POST、expand）" do
      include ActionView::RecordIdentifier

      let(:jackpot) { Dopamine.jackpot_tier }
      let(:rare) { settings.dig(:xp, :tiers).find { |tier| tier[:multiplier] > 1 && tier != jackpot } }

      def post_expand(article)
        post article_reading_path(article), params: { expand: 1 }, headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
      end

      # turbo-stream の中身は <template> に包まれ、HTML4 の parser は template の子を捨てるので外して読む
      def page
        Capybara.string(response.body.gsub(%r{</?template>}, ""))
      end

      def detail(article)
        page.find("turbo-stream[action='replace'][target='#{dom_id(article, :detail)}']")
      end

      it "抽選して行の下を出目の帯・3 行要約・「記事に遷移」で埋める。ルーレットのモーダルは出さない" do
        article = create(:article, url: "https://example.com/a", summary: "・一\n・二\n・三")
        allow(XpRoulette).to receive(:draw).and_return(common)

        travel_to(noon) { post_expand(article) }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(page).to have_no_css("turbo-stream[target='roulette']")
        expect(page).to have_no_css("[data-controller='roulette']")
        box = detail(article)
        expect(box).to have_css("##{dom_id(article, :detail)}[data-swipe-target='detail']")
        expect(box).to have_css("[data-tier='#{common}']", text: "出目 通常 ×1 ・ 完読で +#{base} XP")
        expect(box).to have_css("section[aria-label='要約'][data-state='ready']", text: "・一")
        link = box.find_link("記事に遷移", href: article.url)
        expect(link[:target]).to eq("_blank")
        expect(link[:rel]).to include("noopener")
        expect(article.reload.reading.tier).to eq(common)
        expect(article.reading.opened_at).to eq(noon)
      end

      it "要約待ちの記事なら要約の Job を積み、「作成中」と出来上がりの購読を出す（広げた記事だけ要約する。ADR 0015・0019）" do
        article = create(:article, :awaiting_summary)

        expect { post_expand(article) }.to have_enqueued_job(Claude::SummarizeArticleJob).with(article)

        expect(detail(article)).to have_text("要約を作成中")
        expect(detail(article)).to have_css("turbo-cable-stream-source", visible: :all)
      end

      it "要約済みの記事を広げ直しても Job は積まず、行は 1 つのまま出目を使い回す" do
        article = create(:article, summary: "・済み")
        create(:reading, article: article, tier: rare[:name], opened_at: noon - 1.hour, returned_at: noon - 1.hour + 5.seconds)
        expect(XpRoulette).not_to receive(:draw)

        expect { post_expand(article) }.not_to have_enqueued_job(Claude::SummarizeArticleJob)

        expect(detail(article)).to have_css("[data-tier='#{rare[:name]}']", text: "出目 掘り出し物 ×#{rare[:multiplier]} ・ 完読で +#{base * rare[:multiplier]} XP")
        expect(Reading.count).to eq(1)
      end

      it "要約に失敗した記事・その日の上限なら、その旨を出して「記事に遷移」はそのまま置く" do
        failed = create(:article, :summary_failed)
        post_expand(failed)
        expect(detail(failed)).to have_text("要約できませんでした")
        expect(detail(failed)).to have_link("記事に遷移", href: failed.url)

        exhausted = create(:article, :awaiting_summary)
        allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, exhausted?: true))
        post_expand(exhausted)
        expect(detail(exhausted)).to have_text("今日の要約の上限に達しました")
      end

      it "jackpot でも全画面へは出ず、帯に出目を出すだけ" do
        allow(XpRoulette).to receive(:draw).and_return(jackpot[:name])
        article = create(:article)

        post_expand(article)

        expect(detail(article)).to have_css("[data-tier='#{jackpot[:name]}']", text: "×#{jackpot[:multiplier]} ・ 完読で +#{base * jackpot[:multiplier]} XP")
        expect(page).to have_no_link("ジャックポットへ")
      end

      it "JS が無ければ expand が付いていてもリーダーへ redirect" do
        article = create(:article)

        post article_reading_path(article), params: { expand: 1 }

        expect(response).to redirect_to(read_article_path(article))
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
        button = page.find_link("受け取って読む", href: read_article_path(article))
        expect(button["data-turbo"]).to be_nil
        expect(button["data-action"]).to be_nil
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

    describe "読み終えた（POST /readings/:id/advance）" do
      def post_turbo(reading)
        post advance_reading_path(reading), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
      end

      def page
        Capybara.string(response.body.gsub(%r{</?template>}, ""))
      end

      let(:current) { create(:article, title: "今の記事", published_at: noon) }
      let!(:reading) { create(:reading, article: current, tier: common, opened_at: noon) }

      it "興味なしにした記事は次の 1 本に継ぎ足さず、他に無ければ「全部読んだ」" do
        create(:article, :dismissed, title: "興味なしの記事", published_at: noon - 1.hour)

        travel_to(noon + 4.minutes + 12.seconds) { post_turbo(reading) }

        expect(page).to have_no_text("興味なしの記事")
        expect(page).to have_text("全部読んだ")
        expect(Reading.count).to eq(1)
      end

      it "保存した記事は次の 1 本に継ぎ足さず、その先の未読へ進む" do
        create(:article, :bookmarked, title: "保存した記事", published_at: noon - 1.hour)
        create(:article, title: "その先の記事", published_at: noon - 2.hours)

        travel_to(noon + threshold) { post_turbo(reading) }

        expect(page).to have_no_text("保存した記事")
        expect(page.find("turbo-stream[action='append'][target='reader']")).to have_css("h1", text: "その先の記事")
      end

      it "保存した記事を読み終えても、次は Main の未読（その記事より古い方）から継ぎ足す" do
        current.bookmark!
        create(:article, title: "Main の未読", published_at: noon - 1.hour)

        travel_to(noon + threshold) { post_turbo(reading) }

        expect(reading.reload).to be_completed
        expect(current.reload).to be_bookmarked
        expect(page.find("turbo-stream[action='append'][target='reader']")).to have_css("h1", text: "Main の未読")
      end

      it "complete_after_seconds 以上なら完読。「読み終えた」の form を判定で置き換え、古い方の次の未読を開いて継ぎ足す" do
        create(:article, title: "新しい記事", published_at: noon + 1.hour)
        following = create(:article, title: "次の記事", published_at: noon - 1.hour)
        allow(XpRoulette).to receive(:draw).and_return(common)

        travel_to(noon + 4.minutes + 12.seconds) { post_turbo(reading) }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(reading.reload).to be_completed
        # 完読で未読が 2 本（新しい記事・次の記事）になり、アイコンのバッジも書き直す
        expect(page).to have_css("turbo-stream[action='replace'][target='app-badge'] #app-badge[data-badge-count-value='2']", visible: :all)
        expect(reading.xp).to eq(base)
        divider = page.find("turbo-stream[action='replace'][target='end_reading_#{reading.id}']")
        expect(divider).to have_css("section[aria-label='判定']", text: "読了！")
        expect(divider).to have_text("+#{base} XP")
        expect(divider).to have_text("滞在 4分12秒 ・ 1 本連続")
        expect(divider).to have_text("今日のゴール 1 / #{goal_articles}")
        appended = page.find("turbo-stream[action='append'][target='reader']")
        expect(appended).to have_css("h1", text: "次の記事")
        expect(appended).to have_no_text("新しい記事")
        next_reading = following.reload.reading
        expect(next_reading.tier).to eq(common)
        expect(next_reading.opened_at).to eq(noon + 4.minutes + 12.seconds)
        expect(appended).to have_css("form#end_reading_#{next_reading.id}")
      end

      it "コンボが付いていれば区切りに「n 本連続 ・ コンボ ×C」と、完読ボーナス × C の XP が出る" do
        rare = Dopamine.tier_names.second
        step = settings.dig(:xp, :combo_multiplier_step)
        2.times { |i| create(:reading, :completed, opened_at: noon - (i + 1).hours, returned_at: noon - (i + 1).hours + 5.minutes, completed_at: noon - (i + 1).hours + 5.minutes) }
        reading.update!(tier: rare)

        travel_to(noon + threshold) { post_turbo(reading) }

        multiplier = (1 + step * 2).round(1)
        total = (base * Dopamine.tier(rare)[:multiplier] * multiplier).round
        divider = page.find("section[aria-label='判定']")
        bonus = base * Dopamine.tier(rare)[:multiplier]
        expect(divider).to have_text("読了！ +#{total} XP")
        expect(divider).to have_text("完読ボーナス +#{bonus} ・ コンボ ×#{multiplier} +#{total - bonus}")
        expect(divider).to have_text("3 本連続")
      end

      it "未満なら未完で +0 XP。それでも次へは進む" do
        create(:article, title: "次の記事", published_at: noon - 1.hour)

        travel_to(noon + threshold - 10.seconds) { post_turbo(reading) }

        expect(reading.reload).not_to be_completed
        expect(page).to have_css("section[aria-label='判定']", text: "未完")
        expect(page).to have_text("+0 XP")
        expect(page).to have_text("#{threshold} 秒未満なら XP なし")
        expect(page).to have_css("turbo-stream[action='append'][target='reader'] h1", text: "次の記事")
      end

      it "次の記事が前に開いて判定前の行を持つなら、再抽選せず開き直す" do
        following = create(:article, published_at: noon - 1.hour)
        rare = Dopamine.tier_names.second
        pending = create(:reading, article: following, tier: rare, opened_at: noon - 1.day)
        expect(XpRoulette).not_to receive(:draw)

        travel_to(noon + threshold) { post_turbo(reading) }

        expect(pending.reload.opened_at).to eq(noon + threshold)
        expect(pending.tier).to eq(rare)
      end

      it "継ぎ足す次の記事が要約待ちなら、その要約の Job を積む" do
        following = create(:article, :awaiting_summary, published_at: noon - 1.hour)

        travel_to(noon + threshold) { post_turbo(reading) }

        expect(Claude::SummarizeArticleJob).to have_been_enqueued.with(following).once
        appended = page.find("turbo-stream[action='append'][target='reader']")
        expect(appended).to have_css("turbo-frame#summary_article_#{following.id}", text: "要約を作成中")
        expect(appended).to have_css("[data-controller='summary-refresh'] turbo-cable-stream-source")
      end

      it "古い未読が尽きたら「全部読んだ」と閉じるを継ぎ足す" do
        travel_to(noon + threshold) { post_turbo(reading) }

        appended = page.find("turbo-stream[action='append'][target='reader']")
        expect(appended).to have_text("全部読んだ")
        expect(appended).to have_link("閉じる", href: root_path)
      end

      it "二度目は判定し直さず、同じ区切りと次の記事を返す。次の記事は開き直さない（1 回目の応答が捨てられても進める）" do
        following = create(:article, title: "次の記事", published_at: noon - 1.hour)
        travel_to(noon + threshold) { post_turbo(reading) }
        first = reading.reload.attributes
        next_first = following.reload.reading.attributes

        travel_to(noon + 1.hour) { post_turbo(reading) }

        expect(response).to have_http_status(:ok)
        expect(reading.reload.attributes).to eq(first)
        expect(following.reading.reload.attributes).to eq(next_first)
        expect(page).to have_css("turbo-stream[action='replace'][target='end_reading_#{reading.id}'] section[aria-label='判定']", text: "読了！")
        expect(page).to have_css("turbo-stream[action='append'][target='reader'] h1", text: "次の記事")
      end

      it "今日のゴールに届いたら区切りに「読み切った！」" do
        (goal_articles - 1).times { |i| create(:reading, :completed, opened_at: noon - (i + 1).hours) }

        travel_to(noon + threshold) { post_turbo(reading) }

        expect(page).to have_css("section[aria-label='判定']", text: "今日のゴール #{goal_articles} / #{goal_articles} ・ 読み切った！")
      end

      it "無い行なら 404" do
        post advance_reading_path(0)
        expect(response).to have_http_status(:not_found)
      end

      it "goal 本目の完読なら区切りに「読み切った！」と「宝箱を開く」、goal + 1 本目には出ない" do
        (goal_articles - 1).times { create(:reading, :completed, opened_at: noon - 1.hour) }
        sixth = create(:article, title: "6 本目", published_at: noon - 1.hour)

        travel_to(noon + threshold) { post_turbo(reading) }

        divider = page.find("turbo-stream[action='replace'][target='end_reading_#{reading.id}']")
        expect(divider).to have_text("今日のゴール #{goal_articles} / #{goal_articles} ・ 読み切った！")
        expect(divider).to have_link("宝箱を開く", href: daily_goal_path)
        expect(DailyGoal.find_by(day: ReadingDay.of(noon))).to be_achieved

        travel_to(noon + threshold * 2) { post_turbo(sixth.reload.reading) }

        divider = page.find("turbo-stream[action='replace'][target='end_reading_#{sixth.reading.id}']")
        expect(divider).to have_text("読了！")
        expect(divider).to have_text("読み切った！")
        expect(divider).to have_no_link("宝箱を開く")
        expect(DailyGoal.count).to eq(1)
      end

      it "JS 無しの POST は次の記事のリーダーへ redirect、尽きたら Main へ" do
        following = create(:article, published_at: noon - 1.hour)
        travel_to(noon + threshold) { post advance_reading_path(reading) }
        expect(response).to redirect_to(read_article_path(following))

        travel_to(noon + threshold * 2) { post advance_reading_path(following.reload.reading) }
        expect(response).to redirect_to(root_path)
      end

      it "未ログインならログイン画面へ" do
        delete session_path
        post advance_reading_path(reading)
        expect(response).to redirect_to(new_session_path)
      end
    end

    describe "記事を開いた（POST /readings/:id/start）" do
      it "判定前なら opened_at を今にして 204" do
        reading = create(:reading, opened_at: noon)

        travel_to(noon + 5.minutes) { post start_reading_path(reading) }

        expect(response).to have_http_status(:no_content)
        expect(reading.reload.opened_at).to eq(noon + 5.minutes)
      end

      it "判定済みの行は変えない" do
        reading = create(:reading, opened_at: noon, returned_at: noon + 5.seconds)

        travel_to(noon + 5.minutes) { post start_reading_path(reading) }

        expect(response).to have_http_status(:no_content)
        expect(reading.reload.opened_at).to eq(noon)
      end

      it "CSRF トークンをヘッダで受け取る（fetch で送るので form の hidden は無い）" do
        reading = create(:reading, opened_at: noon)
        ActionController::Base.allow_forgery_protection = true
        get read_article_path(reading.article)
        token = page.find("meta[name='csrf-token']", visible: :all)[:content]

        post start_reading_path(reading)
        expect(response).to have_http_status(:unprocessable_content)

        travel_to(noon + 5.minutes) { post start_reading_path(reading), headers: { "X-CSRF-Token" => token } }
        expect(response).to have_http_status(:no_content)
        expect(reading.reload.opened_at).to eq(noon + 5.minutes)
      ensure
        ActionController::Base.allow_forgery_protection = false
      end

      it "無い行なら 404" do
        post start_reading_path(0)
        expect(response).to have_http_status(:not_found)
      end

      it "未ログインならログイン画面へ" do
        reading = create(:reading, opened_at: noon)
        delete session_path
        post start_reading_path(reading)
        expect(response).to redirect_to(new_session_path)
        expect(reading.reload.opened_at).to eq(noon)
      end
    end

    describe "元サイトへ出て戻る経路は無い" do
      it "POST /readings/return と GET /readings/:id は 404" do
        reading = create(:reading, :completed)

        post "/readings/return"
        expect(response).to have_http_status(:not_found)

        get "/readings/#{reading.id}"
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "Main のコンボと「読む」" do
      it "判定前の記事があっても「読了を記録」のピルは出ない（判定は Reader の「読み終えた」だけ）" do
        create(:reading, article: create(:article, title: "読みかけ"), tier: common, opened_at: noon)

        get root_path

        expect(page).to have_no_button("読了を記録")
        expect(page).to have_no_css("[data-controller='reading-return']")
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

      it "行の「読む」は Turbo の POST（モーダルを受ける）" do
        article = create(:article)
        get root_path
        form = page.find("form[action='#{article_reading_path(article)}']")
        expect(form["data-turbo"]).to be_nil
        expect(form["data-action"]).to be_nil
        expect(form).to have_button("読む")
        expect(page).to have_css("main #roulette")
      end
    end
  end
end
