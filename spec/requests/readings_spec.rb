RSpec.describe "Readings", type: :request do
  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:goal_articles) { settings.dig(:daily_goal, :articles) }
  let(:reset_hour) { settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }
  let(:common) { Dopamine.rarity_names.first }

  def page
    Capybara.string(response.body)
  end

  it "未ログインなら読むはログイン画面へ" do
    article = create(:article)
    post article_reading_path(article)
    expect(response).to redirect_to(new_session_path)
  end

  it "未ログインなら枠の取り直しもログイン画面へ" do
    get tier_reading_path(create(:reading))
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    describe "読む（POST /articles/:id/reading）" do
      it "Reading を作り、アプリ内のリーダーへ redirect する" do
        article = create(:article, url: "https://example.com/a")

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

    describe "一覧の外から読む（Saved の行・宝箱の「もう 1 本だけ」からの POST /articles/:id/reading）" do
      let(:jackpot) { Dopamine.top_rarity }
      let(:rare) { Dopamine.rarity(Dopamine.rarity_names.second) }

      def post_turbo(article)
        post article_reading_path(article), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
      end

      it "モーダルを挟まず、Turbo が辿れる 303 で Reader へ進む" do
        article = create(:article, url: "https://example.com/a")

        travel_to(noon) { post_turbo(article) }

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(read_article_path(article))
        expect(article.reload.reading).to have_attributes(opened_at: noon, tier: common)
      end

      it "判定済みで頂点の段の記事でも、全画面の予告へは出ず Reader へ進む" do
        article = create(:article_judgment, **scores_for(jackpot[:name])).article

        post_turbo(article)

        expect(response).to redirect_to(read_article_path(article))
        expect(article.reload.reading.tier).to eq(jackpot[:name])
      end

      context "判定が設定済み" do
        include_context "判定が設定済み"

        it "Reader の帯は判定中で、段のリールを回しながら枠の到着を購読する。枠が決まった後に開き直すと、止まった帯で購読しない" do
          article = create(:article)

          post_turbo(article)
          follow_redirect!
          reading = article.reload.reading
          expect(reading.tier).to be_nil
          band = page.find("#rarity_reading_#{reading.id}")
          expect(band).to have_css("[data-state='pending'][data-tier='']", text: /判定中.*中身で枠が決まる/)
          expect(band.find(".reel-pending .reel-inner", visible: :all)["data-reel"].split("\n").size).to eq(Dopamine.rarity_names.size + 1)
          expect(band).to have_css("[data-controller='pending-refresh'][data-pending-refresh-url-value='#{tier_reading_path(reading)}'] turbo-cable-stream-source", visible: :all)

          create(:article_judgment, article: article, **scores_for(rare[:name]))
          Reading.settle_tier!(article)
          get read_article_path(article)
          band = page.find("#rarity_reading_#{reading.id}")
          expect(band).to have_css("[data-state='ready'][data-tier='#{rare[:name]}']", text: "#{rare[:min_total]} 点 レア ・ 完読でレアカード")
          expect(band).to have_no_css(".reel, turbo-cable-stream-source, [data-sfx-cue-value]", visible: :all)
        end
      end

      it "未完のまま再び読むと、前回の枠のまま Reader へ進む" do
        article = create(:article)
        create(:reading, article: article, tier: rare[:name], opened_at: noon - 1.hour, returned_at: noon - 1.hour + 5.seconds)

        post_turbo(article)
        follow_redirect!

        expect(page).to have_css("[data-tier='#{rare[:name]}']", text: "レア ・ 完読でレアカード")
        expect(Reading.count).to eq(1)
      end

      # 二重タップで同じ記事の行が同時に作られた: 読み込み時は行が無く、INSERT が一意制約で落ちる
      def race_on(article, existing_tier:)
        create(:reading, article: article, tier: existing_tier, opened_at: noon - 1.hour)
        ghost = Reading.new(article: article)
        allow(Reading).to receive(:find_or_initialize_by).and_return(ghost)
        allow(ghost).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new("二重タップ"))
      end

      it "二重タップで行が同時に作られたら、先に入った行を使って Reader へ進む" do
        article = create(:article)
        race_on(article, existing_tier: rare[:name])

        post_turbo(article)

        expect(response).to redirect_to(read_article_path(article))
        expect(Reading.count).to eq(1)
        expect(article.reload.reading.tier).to eq(rare[:name])
      end

      it "通常の POST（JS 無し）も Reader へ redirect" do
        article = create(:article, url: "https://example.com/a")

        post article_reading_path(article)

        expect(response).to redirect_to(read_article_path(article))
      end
    end

    describe "枠の取り直し（GET /readings/:id/tier。接続前や切断中に配られた枠を、帯が取りに来る）" do
      let(:jackpot) { Dopamine.top_rarity }
      let(:rare) { Dopamine.rarity(Dopamine.rarity_names.second) }
      let(:duration) { Dopamine.settings.dig(:cards, :reveal_duration_ms) }

      def frame(reading)
        get tier_reading_path(reading)
        page.find("turbo-frame#rarity_band_reading_#{reading.id}")
      end

      it "まだ判定中なら、判定中の帯を返す" do
        expect(frame(create(:reading, :pending))).to have_css("[data-state='pending']", text: /判定中/)
      end

      it "枠が決まっていたら、段を 2 周してから止まるリールと、止まった瞬間に鳴る段の音を返す（長さは cards.reveal_duration_ms）" do
        reading = create(:reading, tier: rare[:name])
        create(:article_judgment, article: reading.article, **scores_for(rare[:name]))

        band = frame(reading).find("[data-state='ready'][data-tier='#{rare[:name]}'].tier-glow", text: "#{rare[:min_total]} 点 レア ・ 完読でレアカード")

        names = Dopamine.rarity_names
        before_stop = names * 2 + names.take(names.index(rare[:name]))
        reel = band.find(".reel")
        expect(reel.find(".reel-inner")["data-reel"].split("\n")).to eq(before_stop.map { |name| ApplicationController.helpers.rarity_label(name) })
        expect(reel["style"]).to include("--reel-steps: #{before_stop.size}", "--reel-duration: #{duration}ms")
        expect(reel).to have_text("レア")
        expect(band.find("[data-sfx-cue-value='rare']", visible: :all)["data-sfx-delay-value"]).to eq(duration.to_s)
        expect(band).to have_no_css(".reel-gold")
      end

      it "完読済みの行なら、帯と一緒に区切りの見出しとカードの差し替えも返す（切断中に決まった枠は、区切りにも届いていない）。完読前の行には付けない" do
        completed = create(:reading, :completed, tier: rare[:name])
        create(:article_judgment, article: completed.article, **scores_for(rare[:name]))

        streams = frame(completed).all("turbo-stream[action='replace']", visible: :all)

        expect(streams.map { |node| node[:target] }).to eq(%W[card_title_reading_#{completed.id} card_reading_#{completed.id}])
        html = Capybara.string(response.body.gsub(%r{</?template>}, ""))
        expect(html).to have_css("#card_title_reading_#{completed.id}", text: "レアカードを手に入れた！")
        expect(html).to have_css("li#card_reading_#{completed.id}[data-tier='#{rare[:name]}']")
        expect(html).to have_no_css("li.card-reveal, [role='dialog']")

        expect(frame(create(:reading, tier: rare[:name]))).to have_no_css("turbo-stream", visible: :all)
        expect(frame(create(:reading, :pending, :completed))).to have_no_css("turbo-stream", visible: :all)
      end

      it "頂点の段は金のリールで、欄の中にコインを降らせ、金の音を鳴らす" do
        reading = create(:reading, :jackpot)

        band = frame(reading)

        expect(band).to have_css("[data-tier='#{jackpot[:name]}'].reel-gold", text: "SS レア ・ 完読でSS レアカード")
        expect(band.find("[data-sfx-cue-value='gold']", visible: :all)["data-sfx-delay-value"]).to eq(duration.to_s)
        expect(band).to have_css(".coins span", minimum: 1)
      end

      it "一番下の段は、リールは止まるが光らず鳴らない（毎回だと、上の段が出たときに効かなくなる）" do
        band = frame(create(:reading, tier: common))

        expect(band).to have_css("[data-tier='#{common}'] .reel-inner", text: "ノーマル")
        expect(band).to have_text("判定できず ノーマル ・ 完読でノーマルカード")
        expect(band).to have_no_css(".tier-glow, .coins, [data-sfx-cue-value]", visible: :all)
      end
    end

    describe "行を広げる（Main の行からの Turbo の POST、expand）" do
      include ActionView::RecordIdentifier

      let(:jackpot) { Dopamine.top_rarity }
      let(:rare) { Dopamine.rarity(Dopamine.rarity_names.second) }

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

      it "行の下を枠の帯・3 行要約・「記事に遷移」で埋める" do
        article = create(:article, url: "https://example.com/a", summary: "・一\n・二\n・三")

        travel_to(noon) { post_expand(article) }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        box = detail(article)
        expect(box).to have_css("##{dom_id(article, :detail)}[data-swipe-target='detail']")
        expect(box).to have_css("[data-tier='#{common}']", text: "判定できず ノーマル ・ 完読でノーマルカード")
        expect(box).to have_css("section[aria-label='要約'][data-state='ready']", text: "・一")
        link = box.find_link("記事に遷移", href: article.url)
        expect(link[:target]).to eq("_blank")
        expect(link[:rel]).to include("noopener")
        expect(article.reload.reading.tier).to eq(common)
        expect(article.reading.opened_at).to eq(noon)
        expect(box).to have_css("[data-controller='sheet'][data-sheet-start-url-value='#{start_reading_path(article.reading, from: "main")}']")
        expect(link["data-action"]).to eq("sheet#open")
        form = box.find("form##{dom_id(article.reading, :end)}[data-sheet-target='finish']")
        expect(form[:action]).to eq(advance_reading_path(article.reading, from: "main"))
        expect(form).to have_button("読み終えた")
      end

      context "判定が設定済み" do
        include_context "判定が設定済み"

        it "帯は判定中で、枠の到着を購読する" do
          article = create(:article, summary: "・済み")

          post_expand(article)

          reading = article.reload.reading
          expect(reading.tier).to be_nil
          expect(detail(article)).to have_css("#rarity_reading_#{reading.id} [data-state='pending']", text: /判定中/)
          expect(detail(article)).to have_css("#rarity_reading_#{reading.id} turbo-cable-stream-source", visible: :all)
        end
      end

      it "要約待ちの記事なら要約の Job を積み、「作成中」と出来上がりの購読を出す（広げた記事だけ要約する。ADR 0015・0019）" do
        article = create(:article, :awaiting_summary)

        expect { post_expand(article) }.to have_enqueued_job(Claude::SummarizeArticleJob).with(article)

        expect(detail(article)).to have_text("要約を作成中")
        expect(detail(article)).to have_css("turbo-cable-stream-source", visible: :all)
      end

      it "要約済みの記事を広げ直しても Job は積まず、行は 1 つのまま枠もそのまま" do
        article = create(:article, summary: "・済み")
        create(:reading, article: article, tier: rare[:name], opened_at: noon - 1.hour, returned_at: noon - 1.hour + 5.seconds)

        expect { post_expand(article) }.not_to have_enqueued_job(Claude::SummarizeArticleJob)

        expect(detail(article)).to have_css("[data-tier='#{rare[:name]}']", text: "レア ・ 完読でレアカード")
        expect(detail(article)).to have_no_css(".reel, .coins")
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

      it "開いた時刻は一覧向け（from=main）の start に送る" do
        article = create(:article)

        post_expand(article)

        expect(detail(article)).to have_css("[data-sheet-start-url-value='#{start_reading_path(article.reload.reading, from: "main")}']")
      end

      it "完読済みの記事を（古い一覧から）広げたら、「読み終えた」ではなく区切りを出す" do
        article = create(:article)
        create(:reading, :completed, article: article, opened_at: noon - 1.hour)

        post_expand(article)

        expect(detail(article)).to have_css("section[aria-label='判定']", text: "を手に入れた！")
        expect(detail(article)).to have_no_button("読み終えた")
      end

      it "判定済みで頂点の段でも全画面へは出ず、帯に点と段を出すだけ" do
        article = create(:article_judgment, **scores_for(jackpot[:name])).article

        post_expand(article)

        expect(detail(article)).to have_css("[data-tier='#{jackpot[:name]}']", text: "#{jackpot[:min_total]} 点 SS レア ・ 完読でSS レアカード")
        expect(page).to have_no_css("[role='dialog']")
      end

      it "JS が無ければ expand が付いていてもリーダーへ redirect" do
        article = create(:article)

        post article_reading_path(article), params: { expand: 1 }

        expect(response).to redirect_to(read_article_path(article))
      end
    end

    describe "読み終えた（POST /readings/:id/advance）" do
      include ActionView::RecordIdentifier

      def post_turbo(reading)
        post advance_reading_path(reading), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
      end

      def page
        Capybara.string(response.body.gsub(%r{</?template>}, ""))
      end

      let(:current) { create(:article, title: "今の記事", published_at: noon) }
      let!(:reading) { create(:reading, article: current, tier: common, opened_at: noon) }
      let(:duration_ms) { settings.dig(:cards, :reveal_duration_ms) }

      it "金の完読は区切りが金色" do
        gold = create(:reading, :jackpot, article: create(:article, published_at: noon - 1.hour), opened_at: noon)

        travel_to(noon + threshold) { post_turbo(gold) }

        expect(page).to have_css("section[aria-label='判定'][data-tier='#{gold.tier}'].bg-amber-400", text: "SS レアカードを手に入れた！")
      end

      it "レアの完読は区切りが橙（通常と同じ色）" do
        rare = create(:reading, :rare, article: create(:article, published_at: noon - 1.hour), opened_at: noon)

        travel_to(noon + threshold) { post_turbo(rare) }

        expect(page).to have_css("section[aria-label='判定'][data-tier='#{rare.tier}'].bg-orange-500", text: "レアカードを手に入れた！")
        expect(page).to have_no_css("section[aria-label='判定'].bg-amber-400")
      end

      it "未完の区切りは灰で、枠の色を使わない" do
        gold = create(:reading, :jackpot, article: create(:article, published_at: noon - 1.hour), opened_at: noon)

        travel_to(noon + 5.seconds) { post_turbo(gold) }

        expect(page).to have_css("section[aria-label='判定'][data-completed='false'].bg-gray-200", text: "カードにならなかった")
        expect(page).to have_no_css("section[aria-label='判定'].bg-amber-400")
      end

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

      it "判定済みの記事の区切りには合計点を添える。点の無いまま一番下の段に決まった記事には「判定できず」" do
        judged = create(:reading, tier: Dopamine.rarity_names.second, article: create(:article, published_at: noon - 2.hours), opened_at: noon)
        create(:article_judgment, article: judged.article, **scores_for(judged.tier))

        travel_to(noon + threshold) { [ judged, reading ].each { |r| post_turbo(r) } }

        expect(Capybara.string(ApplicationController.render(partial: "readings/divider", locals: { reading: judged.reload }))).to have_text("読了 ・ #{Dopamine.rarity(judged.tier)[:min_total]} 点")
        expect(page.find("turbo-stream[action='replace'][target='end_reading_#{reading.id}']")).to have_text("読了 ・ 判定できず")
      end

      it "判定中のまま完読したら、段の名を付けず破線の枠のカードで区切り、頂点が後から届いても全画面は出さない。届いた枠は、区切りの見出し・カード・帯へ 1 通で配る" do
        reading.update!(tier: nil)

        travel_to(noon + threshold) { post_turbo(reading) }

        divider = page.find("turbo-stream[action='replace'][target='end_reading_#{reading.id}']")
        expect(divider).to have_css("#card_title_reading_#{reading.id}", text: "読了 ・ 判定中")
        expect(divider).to have_css("#card_title_reading_#{reading.id}", text: "カードを手に入れた！")
        expect(divider).to have_css("li#card_reading_#{reading.id}.border-dashed[data-tier=''] [data-rarity-label]", text: "判定中")
        expect(page).to have_no_css("[role='dialog']")

        top = Dopamine.top_rarity
        create(:article_judgment, article: reading.article, **scores_for(top[:name]))
        stream = Turbo::StreamsChannel.send(:stream_name_from, [ reading, :tier ])
        expect { JudgeArticleJob.settle(reading.article) }.to have_broadcasted_to(stream).with { |html|
          streams = Capybara.string(html.gsub(%r{</?template>}, ""))
          expect(streams.all("turbo-stream").map { |node| node[:target] }).to eq(%W[card_title_reading_#{reading.id} card_reading_#{reading.id} rarity_reading_#{reading.id}]), "帯の差し替えが購読を外すので、帯は最後"
          expect(streams).to have_css("#card_title_reading_#{reading.id}", text: "SS レアカードを手に入れた！")
          expect(streams).to have_css("#card_title_reading_#{reading.id}", text: "読了 ・ #{top[:min_total]} 点")
          expect(streams).to have_css("li#card_reading_#{reading.id}.border-amber-400[data-tier='#{top[:name]}']")
          expect(streams).to have_no_css("li.card-reveal, [role='dialog']")
        }
      end

      it "完読の区切りには手に入れたカードが裏からめくれて出る（長さは yml）。金でなければ全画面は出ない" do
        travel_to(noon + threshold) { post_turbo(reading) }

        divider = page.find("turbo-stream[action='replace'][target='end_reading_#{reading.id}']")
        card = divider.find("ul.card-deck[data-controller='card-deck'] li.card-reveal[data-tier='#{common}']")
        expect(card["style"]).to include("--reveal-duration: #{duration_ms}ms")
        expect(card).to have_css("h3", text: "今の記事")
        expect(card).to have_css(".card-back", text: "DopaFeed")
        expect(page).to have_no_css("[role='dialog']")
      end

      it "金の完読は区切りのカードに加えて全画面の開封が出て、タップで閉じられる（閉じる手段がある）" do
        gold = create(:reading, :jackpot, article: create(:article, title: "金の記事", published_at: noon - 1.hour), opened_at: noon)

        travel_to(noon + threshold) { post_turbo(gold) }

        overlay = page.find("[data-controller='reveal'][role='dialog']")
        expect(overlay).to have_text("SS レアカードを手に入れた！")
        expect(overlay).to have_css("li.card-reveal[data-tier='#{gold.tier}'] h3", text: "金の記事")
        expect(overlay).to have_button("閉じる")
        expect(overlay["data-action"]).to include("reveal#close")
        expect(overlay["data-turbo-temporary"]).not_to be_nil # 画面を移って戻っても蘇らない
        expect(overlay).to have_no_link # 全画面の中のカードは元記事へ飛ばない（押す = 閉じる）
        expect(page).to have_css("##{dom_id(gold, :card)}", count: 1) # 区切りと全画面で同じカードを描くが id は 1 つ
        expect(page.find("section[aria-label='判定']")).to have_link(href: gold.article.url)
      end

      it "未完の区切りにはカードが無い" do
        travel_to(noon + 5.seconds) { post_turbo(reading) }

        expect(page).to have_css("section[aria-label='判定']", text: "カードにならなかった")
        expect(page).to have_no_css("li.card-reveal")
        expect(page).to have_no_css("[role='dialog']")
      end

      it "complete_after_seconds 以上なら完読。「読み終えた」の form を判定で置き換え、古い方の次の未読を開いて継ぎ足す" do
        create(:article, title: "新しい記事", published_at: noon + 1.hour)
        following = create(:article, title: "次の記事", published_at: noon - 1.hour)
        allow(Reading).to receive(:tier_at_open).and_return(common)

        travel_to(noon + 4.minutes + 12.seconds) { post_turbo(reading) }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(reading.reload).to be_completed
        expect(page).to have_css("turbo-stream[action='replace'][target='app-badge'] #app-badge[data-badge-count-value='2']", visible: :all)
        divider = page.find("turbo-stream[action='replace'][target='end_reading_#{reading.id}']")
        expect(divider).to have_css("section[aria-label='判定'][data-completed='true'][data-tier='#{common}']", text: "ノーマルカードを手に入れた！")
        expect(divider).to have_no_text("XP")
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

      it "連続完読していれば区切りに「n 本連続」。レアの枠なら「レアカードを手に入れた！」" do
        rare = Dopamine.rarity_names.second
        2.times { |i| create(:reading, :completed, opened_at: noon - (i + 1).hours, returned_at: noon - (i + 1).hours + 5.minutes, completed_at: noon - (i + 1).hours + 5.minutes) }
        reading.update!(tier: rare)

        travel_to(noon + threshold) { post_turbo(reading) }

        divider = page.find("section[aria-label='判定'][data-tier='#{rare}']")
        expect(divider).to have_text("レアカードを手に入れた！")
        expect(divider).to have_text("3 本連続")
        expect(divider).to have_no_text("×")
      end

      it "未満なら未完でカードにならない。それでも次へは進む" do
        create(:article, title: "次の記事", published_at: noon - 1.hour)

        travel_to(noon + threshold - 10.seconds) { post_turbo(reading) }

        expect(reading.reload).not_to be_completed
        expect(page).to have_css("section[aria-label='判定'][data-completed='false']", text: "カードにならなかった")
        expect(page).to have_text("#{threshold} 秒以上読むと手に入る")
        expect(page).to have_no_text("XP")
        expect(page).to have_css("turbo-stream[action='append'][target='reader'] h1", text: "次の記事")
      end

      it "次の記事が前に開いて判定前の行を持つなら、再抽選せず開き直す" do
        following = create(:article, published_at: noon - 1.hour)
        rare = Dopamine.rarity_names.second
        pending = create(:reading, article: following, tier: rare, opened_at: noon - 1.day)

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
        expect(appended).to have_css("[data-controller='pending-refresh'] turbo-cable-stream-source")
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
        expect(page).to have_css("turbo-stream[action='replace'][target='end_reading_#{reading.id}'] section[aria-label='判定']", text: "カードを手に入れた！")
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
        expect(divider).to have_css("a[href='#{daily_goal_path}'][data-turbo-prefetch='false']") # 先読みだけでフィナーレを使い切らない
        expect(divider.find_link("宝箱を開く")[:class]).to include("[-webkit-touch-callout:none]") # 長押しのプレビューでも使い切らない
        expect(DailyGoal.find_by(day: ReadingDay.of(noon))).to be_achieved

        travel_to(noon + threshold * 2) { post_turbo(sixth.reload.reading) }

        divider = page.find("turbo-stream[action='replace'][target='end_reading_#{sixth.reading.id}']")
        expect(divider).to have_text("カードを手に入れた！")
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

    describe "一覧の広げた欄から読み終えた（POST /readings/:id/advance?from=main）" do
      include ActionView::RecordIdentifier

      def post_main(reading)
        post advance_reading_path(reading, from: "main"), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
      end

      def page
        Capybara.string(response.body.gsub(%r{</?template>}, ""))
      end

      let(:current) { create(:article, title: "今の記事", published_at: noon) }
      let!(:reading) { create(:reading, article: current, tier: common, opened_at: noon) }

      it "一覧の広げた欄の区切りにも、手に入れたカードがめくれて出る" do
        travel_to(noon + threshold) { post_main(reading) }

        divider = page.find("turbo-stream[action='replace'][target='#{dom_id(reading, :end)}']")
        expect(divider).to have_css("ul.card-deck li.card-reveal[data-tier='#{common}'] h3", text: "今の記事")
      end

      it "金の完読でも一覧では全画面の開封は出さず、SS レアカードがめくれるだけ（ADR 0019）" do
        gold = create(:reading, :jackpot, article: create(:article, title: "一覧の金", published_at: noon), opened_at: noon)

        travel_to(noon + threshold) { post_main(gold) }

        divider = page.find("turbo-stream[action='replace'][target='#{dom_id(gold, :end)}']")
        expect(divider).to have_css("ul.card-deck li.card-reveal[data-tier='#{gold.tier}'] h3", text: "一覧の金")
        expect(page).to have_no_css("[role='dialog']")
      end

      it "判定して「読み終えた」を区切りに替え、ステータス行と未読数を書き直す。次の記事は開かず、その要約も積まない（ADR 0019）" do
        following = create(:article, :awaiting_summary, title: "次の記事", published_at: noon - 1.hour)

        expect do
          travel_to(noon + threshold) { post_main(reading) }
        end.not_to have_enqueued_job(Claude::SummarizeArticleJob)

        expect(response).to have_http_status(:ok)
        expect(reading.reload).to be_completed
        expect(following.reload.reading).to be_nil
        expect(page.find("turbo-stream[action='replace'][target='#{dom_id(reading, :end)}']")).to have_css("section[aria-label='判定']", text: "ノーマルカードを手に入れた！")
        status = page.find("turbo-stream[action='replace'][target='status-card']")
        expect(status).to have_css("section#status-card[aria-label='今日の進み']")
        expect(status).to have_text("今日のゴール 1 / #{goal_articles}", normalize_ws: true)
        expect(status).to have_text("図鑑 1 枚", normalize_ws: true)
        expect(status).to have_no_text("XP")
        expect(page.find("turbo-stream[action='replace'][target='unread-badge']")).to have_css("[data-unread-badge]", text: "1")
        expect(page).to have_css("turbo-stream[action='replace'][target='app-badge']")
        expect(page).to have_no_css("turbo-stream[target='reader']")
        expect(page).to have_no_text("次の記事")
      end

      it "すぐ戻ったら未完でカードにならない。ステータスの本数は変わらない" do
        travel_to(noon + 5.seconds) { post_main(reading) }

        expect(page).to have_css("section[aria-label='判定']", text: "カードにならなかった")
        expect(page.find("turbo-stream[target='status-card']")).to have_text("今日のゴール 0 / #{goal_articles}", normalize_ws: true)
        expect(reading.reload).not_to be_completed
      end

      it "goal 本目なら区切りに「宝箱を開く」" do
        (goal_articles - 1).times { |i| create(:reading, :completed, opened_at: noon - (i + 1).hours) }

        travel_to(noon + threshold) { post_main(reading) }

        expect(page).to have_link("宝箱を開く", href: daily_goal_path)
      end

      it "二度目は判定し直さず同じ区切りを返す（1 回目の応答が捨てられても区切りが出る）" do
        travel_to(noon + threshold) { post_main(reading) }
        first = reading.reload.attributes

        travel_to(noon + threshold * 3) { post_main(reading) }

        expect(reading.reload.attributes).to eq(first)
        expect(page).to have_css("section[aria-label='判定']", text: "ノーマルカードを手に入れた！")
        expect(Reading.count).to eq(1)
      end

      it "未完なら区切りの後ろに「読み終えた」を置き直し、前の区切りは消す（同じ欄で読み直せるように）" do
        travel_to(noon + 5.seconds) { post_main(reading) }

        expect(page).to have_css("turbo-stream[action='remove'][target='#{dom_id(reading, :result)}']")
        replaced = page.find("turbo-stream[action='replace'][target='#{dom_id(reading, :end)}']")
        expect(replaced).to have_css("section[aria-label='判定']", text: "カードにならなかった")
        form = replaced.find("form##{dom_id(reading, :end)}[data-sheet-target='finish']")
        expect(form[:action]).to eq(advance_reading_path(reading, from: "main"))
      end

      it "完読なら「読み終えた」は置き直さない" do
        travel_to(noon + threshold) { post_main(reading) }

        expect(page.find("turbo-stream[action='replace'][target='#{dom_id(reading, :end)}']")).to have_no_css("form", visible: :all)
      end

      it "JS 無しの POST は Main へ戻る" do
        create(:article, published_at: noon - 1.hour)

        travel_to(noon + threshold) { post advance_reading_path(reading, from: "main") }

        expect(response).to redirect_to(root_path)
        expect(Reading.count).to eq(1)
      end
    end

    describe "記事を開いた（POST /readings/:id/start）" do
      it "判定前なら opened_at を今にして 204" do
        reading = create(:reading, opened_at: noon)

        travel_to(noon + 5.minutes) { post start_reading_path(reading) }

        expect(response).to have_http_status(:no_content)
        expect(reading.reload.opened_at).to eq(noon + 5.minutes)
      end

      it "一覧の広げた欄から（from=main）なら、未完で判定済みの行も開き直して測り直す（同じ欄で読み直せる）。完読済みは変えない" do
        incomplete = create(:reading, opened_at: noon, returned_at: noon + 5.seconds)
        completed = create(:reading, :completed, opened_at: noon)
        before = completed.returned_at

        travel_to(noon + 5.minutes) do
          post start_reading_path(incomplete, from: "main")
          post start_reading_path(completed, from: "main")
        end

        expect(response).to have_http_status(:no_content)
        expect(incomplete.reload.opened_at).to eq(noon + 5.minutes)
        expect(incomplete.returned_at).to be_nil
        expect(completed.reload.returned_at).to eq(before)
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

      it "今日 3 本連続完読していれば「3 連続」、1 本だけ・無しなら出ない" do
        travel_to noon do
          get root_path
          expect(page).to have_no_css("section[aria-label='今日の進み'] span", text: /\A\d+ 連続\z/)

          create(:reading, :completed, opened_at: noon - 3.hours)
          get root_path
          expect(page).to have_no_css("section[aria-label='今日の進み'] span", text: /\A\d+ 連続\z/)

          2.times { |i| create(:reading, :completed, opened_at: noon - (i + 1).hours) }
          get root_path
          expect(page).to have_css("section[aria-label='今日の進み'] span", text: "3 連続")
        end
      end

      it "行の「読む」は Turbo の POST" do
        article = create(:article)
        get root_path
        form = page.find("form[action='#{article_reading_path(article)}']")
        expect(form["data-turbo"]).to be_nil
        expect(form["data-action"]).to be_nil
        expect(form).to have_button("読む")
      end
    end
  end
end
