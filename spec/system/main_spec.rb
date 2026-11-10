# Main を 390×844 で開く。見た目の崩れ（横スクロール・タップ領域）と、ログイン → Main → 設定 → サインアウトの動線
RSpec.describe "Main", type: :system do
  let(:goal_articles) { Dopamine.settings.dig(:daily_goal, :articles) }
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 10, 20, reset_hour) + 8.hours }

  it "未読 3 本と今日のゴール 3 / N が出て、横スクロールが無く、タップ領域は 44px 以上" do
    feed = create(:feed, title: "Ruby Weekly")
    3.times { |i| create(:article, feed: feed, title: "記事 #{i + 1} のとても長い見出しが 390 幅で折り返されること", published_at: noon - i.hours) }
    travel_to noon do
      3.times { create(:reading, :completed, opened_at: noon - 1.hour) }
      sign_in

      expect(page).to have_css("article", count: 3)
      expect(find("section[aria-label='今日の進み']")).to have_text("今日のゴール 3 / #{goal_articles}", normalize_ws: true)
      expect(page).to have_text("1日連続")

      # CSS が当たっていないと以下の寸法検査が全部落ちて原因が読めないので、先に 1 つのユーティリティで確かめる
      expect(page.evaluate_script("getComputedStyle(document.body).backgroundColor")).not_to eq("rgba(0, 0, 0, 0)"), "Tailwind の CSS が当たっていない（bin/rails tailwindcss:build を先に）"
      expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
      small = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll("a, button")).filter(el => el.getClientRects().length > 0).map(el => {
          const r = el.getBoundingClientRect();
          return [el.textContent.trim() || el.getAttribute("aria-label"), Math.round(r.width), Math.round(r.height)];
        }).filter(([, w, h]) => w < 44 || h < 44)
      JS
      expect(small).to be_empty, "44px 未満のタップ領域: #{small.inspect}"
    end
  end

  it "行は詰めて並び、見出しのどこを押しても「読む」になる" do
    feed = create(:feed, title: "Zenn")
    6.times do |i|
      create(:article, feed: feed, title: "見出しが三行に折り返されるくらいに長い記事の題名をここに書いておく、その #{i + 1} 本目の記事",
                       image_url: "/icon.png", published_at: 1.hour.ago - i.minutes)
    end
    sign_in

    heights = page.evaluate_script("Array.from(document.querySelectorAll('article')).map(el => el.getBoundingClientRect().height)")
    expect(heights.size).to eq(6)
    expect(heights.max).to be <= 120, "行が高い（一画面に並ぶ本数が減る）: #{heights.inspect}"
    expect(page).to have_no_button("削除")
    expect(page).to have_no_text("興味なし")
    # 「読む」はボタンの名前だけで、目に見える文字は出さない
    expect(page).to have_css("article button[data-swipe-target='read'] > span.sr-only", text: "を読む", visible: :all, count: 6)
    expect(page.evaluate_script("Array.from(document.querySelectorAll('article button[data-swipe-target=read]')).every(b => b.querySelector('.sr-only').getBoundingClientRect().width <= 1)")).to be(true)
    screenshot!("list")

    # 見出しの上も画像の上も、指が触れるのは行を覆う「読む」のボタン
    row = find("article", text: "その 3 本目")
    receivers = row.evaluate_script(<<~JS)
      ["h2", "time", "figure"].map(selector => {
        const r = this.querySelector(selector).getBoundingClientRect()
        return document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2).dataset.swipeTarget
      })
    JS
    expect(receivers).to eq(%w[read read read])
    row.find_button("読む").click
    expect(page).to have_link("記事に遷移")
    expect(page).to have_no_css("[role='dialog'][aria-label='ルーレット']")
    expect(Article.where("title LIKE ?", "%その 3 本目%").sole.reading).to be_present
  end

  describe "行をタップすると下に広がる（ADR 0019）" do
    let(:common) { Dopamine.rarity_names.first }
    let(:rare) { Dopamine.rarity(Dopamine.rarity_names.second) }

    def expand(title)
      find("article", text: title).find_button("読む").click
    end

    def expanded?(title)
      find("article", text: title).find_button("読む")["aria-expanded"] == "true"
    end

    it "画面を移らずに出目の帯・3 行要約・「記事に遷移」が出て、もう一度タップで畳む。別の行を広げると前の行は畳む" do
      allow(RarityDraw).to receive(:draw).and_return(common)
      first = create(:article, title: "最初の記事", url: "https://example.com/first", summary: "・一行目\n・二行目\n・三行目", image_url: "/icon.png", published_at: 1.hour.ago)
      create(:article, title: "次の記事", summary: "・次の要約", published_at: 2.hours.ago)
      create(:article, title: "三本目の記事", published_at: 3.hours.ago)
      sign_in

      expand("最初の記事")
      detail = find("##{ActionView::RecordIdentifier.dom_id(first, :detail)}")
      expect(detail).to have_text("出目 通常 ・ 完読で通常カード")
      expect(detail).to have_css("section[aria-label='要約']", text: "・一行目")
      link = detail.find_link("記事に遷移", href: first.url)
      expect(link[:target]).to eq("_blank")
      expect(page).to have_current_path(root_path)
      expect(expanded?("最初の記事")).to be(true)
      # 広げた欄は行の真下に出て、次の行はその下へ押し下がる
      row_bottom, box_top, box_bottom, next_top = page.evaluate_script(<<~JS)
        [document.querySelectorAll("article")[0].getBoundingClientRect().bottom,
         document.getElementById("#{detail[:id]}").getBoundingClientRect().top,
         document.getElementById("#{detail[:id]}").getBoundingClientRect().bottom,
         document.querySelectorAll("article")[1].getBoundingClientRect().top]
      JS
      expect(box_top).to be >= row_bottom - 1
      expect(next_top).to be >= box_bottom - 1
      expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
      expect(link.evaluate_script("this.getBoundingClientRect().height")).to be >= 44
      screenshot!("expanded")

      # 2 度目のタップは送らずに畳む。もう一度で開く
      page.execute_script("window.__submits = 0; document.addEventListener('turbo:submit-start', () => window.__submits++)")
      expand("最初の記事")
      expect(page).to have_no_link("記事に遷移")
      expect(expanded?("最初の記事")).to be(false)
      expand("最初の記事")
      expect(page).to have_link("記事に遷移", count: 1)
      expect(page.evaluate_script("window.__submits")).to eq(0)

      # 別の行を広げると前の行は畳む
      expand("次の記事")
      expect(page).to have_text("・次の要約")
      expect(page).to have_link("記事に遷移", count: 1)
      expect(page).to have_no_text("・一行目")
      expect(expanded?("最初の記事")).to be(false)
      expect(Reading.count).to eq(2)

      # 読み込み済みの行を送らずに開き直しても、開いていた行は畳む
      page.execute_script("window.__submits = 0")
      expand("最初の記事")
      expect(page).to have_text("・一行目")
      expect(page).to have_no_text("・次の要約")
      expect(expanded?("次の記事")).to be(false)
      expect(page.evaluate_script("window.__submits")).to eq(0)
    end

    it "応答を待つ間に別の行を押したら、最後に押した行だけが開く（送信は順に届く）" do
      create(:article, title: "最初の記事", summary: "・一行目", published_at: 1.hour.ago)
      create(:article, title: "次の記事", summary: "・次の要約", published_at: 2.hours.ago)
      create(:article, title: "三本目の記事", summary: "・三本目の要約", published_at: 3.hours.ago)
      sign_in
      expand("三本目の記事")
      expect(page).to have_text("・三本目の要約")

      # POST の応答を手で放すまで止める（圏外で応答が遅い状態）
      page.execute_script(<<~JS)
        window.__held = []
        window.__fetch = window.fetch
        window.fetch = (url, options) => (options?.method || "GET").toUpperCase() === "POST"
          ? new Promise((resolve) => window.__held.push(() => window.__fetch(url, options).then(resolve)))
          : window.__fetch(url, options)
        window.__release = () => { const next = window.__held.shift(); if (next) next() }
      JS
      expand("最初の記事")
      expand("次の記事")
      # 応答を待つ間に、読み込み済みの行を送らずに開き、最後に押した行にする
      expand("三本目の記事")
      expand("三本目の記事")
      expect(expanded?("三本目の記事")).to be(true)
      Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until page.evaluate_script("window.__held.length") == 1 }
      page.execute_script("window.__release()")
      expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(Article.find_by!(title: "最初の記事"), :detail)}", visible: :all)
      Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until page.evaluate_script("window.__held.length") == 1 }
      page.execute_script("window.__release()")
      expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(Article.find_by!(title: "次の記事"), :detail)} section", visible: :all)

      expect(page).to have_text("・三本目の要約")
      expect(page).to have_no_text("・一行目")
      expect(page).to have_no_text("・次の要約")
      expect(expanded?("三本目の記事")).to be(true)
    end

    it "応答を待つ間に別の未読の行も押したら、後に押した行が開く" do
      create(:article, title: "最初の記事", summary: "・一行目", published_at: 1.hour.ago)
      create(:article, title: "次の記事", summary: "・次の要約", published_at: 2.hours.ago)
      sign_in
      page.execute_script(<<~JS)
        window.__held = []
        window.__fetch = window.fetch
        window.fetch = (url, options) => (options?.method || "GET").toUpperCase() === "POST"
          ? new Promise((resolve) => window.__held.push(() => window.__fetch(url, options).then(resolve)))
          : window.__fetch(url, options)
        window.__release = () => { const next = window.__held.shift(); if (next) next() }
      JS
      expand("最初の記事")
      expand("次の記事")
      2.times do
        Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until page.evaluate_script("window.__held.length") >= 1 }
        page.execute_script("window.__release()")
      end

      expect(page).to have_text("・次の要約")
      expect(page).to have_no_text("・一行目")
      expect(expanded?("次の記事")).to be(true)
      expect(expanded?("最初の記事")).to be(false)
    end

    it "別の画面から戻る（Turbo のキャッシュ）と、離れたときの開閉のまま。畳んで離れた行は開き直さない" do
      create(:article, title: "最初の記事", summary: "・一行目", published_at: 1.hour.ago)
      create(:article, title: "次の記事", summary: "・次の要約", published_at: 2.hours.ago)
      sign_in

      expand("最初の記事")
      expect(page).to have_text("・一行目")
      expand("次の記事")
      expect(page).to have_text("・次の要約")
      expand("次の記事")
      expect(page).to have_no_link("記事に遷移")

      find("section[aria-label='今日の進み']").click_link
      expect(page).to have_current_path(daily_goal_path)
      page.go_back
      expect(page).to have_current_path(root_path)
      expect(page).to have_css("article", count: 2)
      expect(page).to have_no_link("記事に遷移")
      expect(expanded?("最初の記事")).to be(false)
      expect(expanded?("次の記事")).to be(false)

      # 開いたまま離れると、戻っても開いたまま 1 行だけ
      expand("最初の記事")
      expect(page).to have_text("・一行目")
      find("section[aria-label='今日の進み']").click_link
      expect(page).to have_current_path(daily_goal_path)
      page.go_back
      expect(page).to have_link("記事に遷移", count: 1)
      expect(expanded?("最初の記事")).to be(true)
    end

    it "「記事に遷移」で元記事を別窓に開いて戻ると、広げた欄に区切りが出て、上の 1 行の本数と枚数が増える。画面は移らない" do
      threshold = Dopamine.settings.dig(:read, :complete_after_seconds)
      goal = Dopamine.settings.dig(:daily_goal, :articles)
      allow(RarityDraw).to receive(:draw).and_return(common)
      article = create(:article, title: "読む記事", summary: "・要約", url: "#{Capybara.current_session.server.base_url}/up?main")
      create(:article, title: "残る記事", published_at: 1.day.ago)
      sign_in
      expect(find("section[aria-label='今日の進み']")).to have_text("今日のゴール 0 / #{goal}", normalize_ws: true)

      expand("読む記事")
      expect(page).to have_link("記事に遷移")
      expect(page).to have_no_button("読み終えた") # 開くまでは隠す
      reading = article.reload.reading
      since = reading.opened_at
      main = current_window
      source = window_opened_by { click_on "記事に遷移" }
      within_window(source) do
        expect(page).to have_current_path("/up", ignore_query: true)
        Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until reading.reload.opened_at > since }
        reading.update_columns(opened_at: Time.current - threshold - 5)
      end
      source.close
      switch_to_window(main)

      expect(page).to have_css("section[aria-label='判定']", text: "通常カードを手に入れた！")
      expect(find("section[aria-label='今日の進み']")).to have_text("今日のゴール 1 / #{goal}", normalize_ws: true)
      expect(find("section[aria-label='今日の進み']")).to have_text("図鑑 1 枚", normalize_ws: true)
      expect(page).to have_current_path(root_path)
      expect(page).to have_css("article", text: "残る記事")
      expect(reading.reload).to be_completed
      expect(Reading.count).to eq(1) # 次の記事は開かない
      expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
      screenshot!("judged")
    end

    # 別窓を開かせず、隠れる・見える合図を手で出す（iPhone のシートの開閉の代わり。reader_spec と同じ手）
    def fake_sheet!
      page.execute_script(<<~JS)
        document.addEventListener("click", (event) => { if (event.target.closest("a[target=_blank]")) event.preventDefault() }, true)
        window.__visibility = "visible"
        Object.defineProperty(document, "visibilityState", { configurable: true, get: () => window.__visibility })
        window.__setVisibility = (state) => { window.__visibility = state; document.dispatchEvent(new Event("visibilitychange")) }
      JS
    end

    def open_link(title)
      link = find("li", text: title).find_link("記事に遷移")
      reading = Article.find_by!(title: title).reading
      since = reading.reload.opened_at
      link.click
      Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until reading.reload.opened_at > since }
      reading
    end

    def leave_and_return(dwell: nil, reading: nil)
      page.execute_script('window.__setVisibility("hidden")')
      reading.update_columns(opened_at: Time.current - dwell) if dwell
      page.execute_script('window.__setVisibility("visible")')
    end

    it "未完の後も同じ欄で読み直せて、2 度目は開いた後に出る「読み終えた」でも判定できる。未読数は完読で 1 減る" do
      threshold = Dopamine.settings.dig(:read, :complete_after_seconds)
      create(:article, title: "読み直す記事", summary: "・要約")
      create(:article, title: "残る記事", published_at: 1.day.ago)
      sign_in
      fake_sheet!
      expect(find("[data-unread-badge]")).to have_text("2")

      expand("読み直す記事")
      reading = open_link("読み直す記事")
      leave_and_return
      expect(page).to have_css("section[aria-label='判定']", text: "カードにならなかった")
      expect(page).to have_no_button("読み終えた")
      expect(find("[data-unread-badge]")).to have_text("2")

      open_link("読み直す記事")
      expect(reading.reload.returned_at).to be_nil
      reading.update_columns(opened_at: Time.current - threshold - 5)
      click_on "読み終えた"

      expect(page).to have_css("section[aria-label='判定']", text: "を手に入れた！")
      expect(page).to have_css("section[aria-label='判定']", count: 1)
      expect(find("[data-unread-badge]")).to have_text("1")
      expect(reading.reload).to be_completed
    end

    it "開いた知らせが戻りより遅れて届いても、判定は知らせの後に送り、開き直しで判定が消えない" do
      create(:article, title: "遅れる記事", summary: "・要約")
      sign_in
      fake_sheet!
      # iOS で凍って開いた知らせ（start）が戻りの後に出ていく様子を、知らせを手で止めて作る
      page.execute_script(<<~JS)
        const original = window.fetch
        let release
        const held = new Promise((resolve) => { release = resolve })
        window.__releaseStart = () => release()
        window.fetch = (url, options) => String(url).includes("/start") ? held.then(() => original(url, options)) : original(url, options)
      JS

      expand("遅れる記事")
      find("li", text: "遅れる記事").find_link("記事に遷移").click
      leave_and_return
      expect(page).to have_no_css("section[aria-label='判定']")

      page.execute_script("window.__releaseStart()")
      expect(page).to have_css("section[aria-label='判定']", text: "カードにならなかった")
      expect(Article.find_by!(title: "遅れる記事").reading.reload.returned_at).to be_present
    end

    it "手押しの「読み終えた」で未完になったら、置き直した「読み終えた」は開き直すまで隠す" do
      create(:article, title: "手で送る記事", summary: "・要約")
      sign_in
      fake_sheet!

      expand("手で送る記事")
      reading = open_link("手で送る記事")
      click_on "読み終えた" # 戻りの合図が来ない端末

      expect(page).to have_css("section[aria-label='判定']", text: "カードにならなかった")
      expect(page).to have_no_button("読み終えた")
      expect(reading.reload.returned_at).to be_present

      open_link("手で送る記事")
      expect(page).to have_button("読み終えた")
      expect(reading.reload.returned_at).to be_nil
    end

    it "手押しの「読み終えた」も行の送信の列に並び、送信中の興味なしの応答を捨てさせない" do
      create(:article, title: "読む記事", summary: "・要約", published_at: 1.hour.ago)
      create(:article, title: "消す記事", published_at: 2.hours.ago)
      # 興味なしの応答を遅らせ、その間に「読み終えた」を押す
      allow_any_instance_of(DismissalsController).to receive(:create).and_wrap_original do |original, *args|
        sleep 1
        original.call(*args)
      end
      sign_in
      fake_sheet!

      expand("読む記事")
      open_link("読む記事")
      page.execute_script(<<~JS)
        const row = document.querySelector("li#article_#{Article.find_by!(title: "消す記事").id}")
        window.Stimulus.getControllerForElementAndIdentifier(row, "swipe").submit(-1)
      JS
      click_on "読み終えた"

      expect(page).to have_css("section[aria-label='判定']", text: "カードにならなかった")
      expect(page).to have_text("1 件を削除しました")
      expect(page).to have_no_css("article", text: "消す記事")
      expect(Article.find_by!(title: "消す記事")).to be_dismissed
    end

    it "戻りの合図で列に預けた後の手押しは、先に待つ興味なしを追い越さない" do
      create(:article, title: "読む記事", summary: "・要約", published_at: 1.hour.ago)
      create(:article, title: "消す記事", published_at: 2.hours.ago)
      allow_any_instance_of(DismissalsController).to receive(:create).and_wrap_original do |original, *args|
        sleep 1
        original.call(*args)
      end
      sign_in
      fake_sheet!

      expand("読む記事")
      open_link("読む記事")
      page.execute_script(<<~JS)
        const row = document.querySelector("li#article_#{Article.find_by!(title: "消す記事").id}")
        window.Stimulus.getControllerForElementAndIdentifier(row, "swipe").submit(-1)
      JS
      leave_and_return # 自動送信は興味なしの後ろで待つ
      click_on "読み終えた"

      expect(page).to have_css("section[aria-label='判定']", text: "カードにならなかった")
      expect(page).to have_text("1 件を削除しました")
      expect(page).to have_no_css("article", text: "消す記事")
    end

    it "畳んだ行は戻りの合図で判定しない（開いたまま合図が来なかった行が、別の行の戻りで判定されない）" do
      threshold = Dopamine.settings.dig(:read, :complete_after_seconds)
      create(:article, title: "最初の記事", summary: "・一行目", published_at: 1.hour.ago)
      create(:article, title: "次の記事", summary: "・次の要約", published_at: 2.hours.ago)
      sign_in
      fake_sheet!

      expand("最初の記事")
      first = open_link("最初の記事") # 隠れる合図が来ないまま戻った
      expand("次の記事")
      expect(expanded?("最初の記事")).to be(false)
      second = open_link("次の記事")
      leave_and_return(dwell: threshold + 5, reading: second)

      expect(page).to have_css("section[aria-label='判定']", text: "を手に入れた！", count: 1)
      expect(second.reload).to be_completed
      expect(first.reload.returned_at).to be_nil
      expect(find("section[aria-label='今日の進み']")).to have_text("今日のゴール 1 /", normalize_ws: true)
    end

    it "要約がまだなら「作成中」、Job が書き終えると広げた欄の要約だけ差し替わる" do
      summarizer = instance_double(Claude::Summarizer, call: "・できた要約\n・二\n・三")
      allow(Claude::Summarizer).to receive(:new).and_return(summarizer)
      article = create(:article, :awaiting_summary, title: "要約待ちの記事")
      sign_in

      expand("要約待ちの記事")
      expect(page).to have_text("要約を作成中")
      expect(page).to have_link("記事に遷移")
      find("turbo-cable-stream-source[connected]", visible: :all)
      screenshot!("pending")

      Claude::SummarizeArticleJob.perform_now(article)

      expect(page).to have_css("section[aria-label='要約']", text: "・できた要約")
      expect(page).to have_no_text("要約を作成中")
      expect(page).to have_current_path(root_path)
    end

    it "レアの出目は帯が橙で光り、モーダルは出ない" do
      allow(RarityDraw).to receive(:draw).and_return(rare[:name])
      create(:article, title: "当たりの記事", summary: "・当たり")
      sign_in

      expand("当たりの記事")
      band = find("[data-tier='#{rare[:name]}']", text: "出目 レア ・ 完読でレアカード")
      expect(band[:class]).to include("tier-glow", "bg-orange-500")
      expect(page).to have_no_css("[role='dialog']")
      screenshot!("rare")
    end

    it "頂点の出目でも全画面へは進まず、帯が金で光る" do
      jackpot = Dopamine.top_rarity
      allow(RarityDraw).to receive(:draw).and_return(jackpot[:name])
      create(:article, title: "大当たりの記事", summary: "・大当たり")
      sign_in

      expand("大当たりの記事")
      band = find("[data-tier='#{jackpot[:name]}']", text: "出目 金 ・ 完読で金のカード")
      expect(band[:class]).to include("tier-glow", "bg-amber-400")
      expect(page).to have_current_path(root_path)
      expect(page).to have_no_text("JACKPOT")
      screenshot!("jackpot")
    end
  end

  it "ステータスは 1 行に収まり、大きな数でも横にはみ出さない。画像つきの行が 6 本目まで画面に入る" do
    feed = create(:feed, title: "Zenn")
    6.times do |i|
      create(:article, feed: feed, title: "見出しが三行に折り返されるくらいに長い記事の題名をここに書いておく、その #{i + 1} 本目の記事",
                       image_url: "/icon.png", published_at: 1.hour.ago - i.minutes)
    end
    travel_to noon do
      goal_articles.times { |i| create(:reading, :completed, opened_at: noon - (i + 1).hours) }
      allow(Reading).to receive(:card_count).and_return(1239)
      sign_in

      status = find("section[aria-label='今日の進み']")
      expect(status).to have_text("1,239 枚", normalize_ws: true)
      expect(status).to have_text("#{goal_articles} 連続", normalize_ws: true)
      expect(status.evaluate_script("this.getBoundingClientRect().height")).to be <= 56
      expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
      overflow = status.evaluate_script("Array.from(this.querySelectorAll('*')).some(el => el.getBoundingClientRect().right > this.getBoundingClientRect().right + 0.5)")
      expect(overflow).to be(false), "ステータスの中身が右にはみ出している"

      tab_top = page.evaluate_script("document.querySelector(\"nav[aria-label='タブバー']\").getBoundingClientRect().top")
      # iPhone のホーム画面アプリは上下のセーフエリア（上 47px・下 34px）の分だけ狭いので、それを引いても 6 本目の見出しの頭が見える
      sixth = page.evaluate_script("document.querySelectorAll('article')[5].querySelector('h2').getBoundingClientRect().top")
      expect(sixth + 47).to be < tab_top - 34, "セーフエリアを引くと 6 本目の見出しが隠れる"
      screenshot!
    end
  end

  it "ストリーク 3 桁・ゴール超え・枚数 6 桁でもステータスは 1 行のまま横にはみ出さない（枚数の末尾を省く）" do
    allow(ReadingStreak).to receive(:days).and_return(365)
    travel_to noon do
      (goal_articles * 2 + 2).times { |i| create(:reading, :completed, opened_at: noon - (i + 1).minutes) }
      allow(Reading).to receive(:card_count).and_return(123_456)
      sign_in

      status = find("section[aria-label='今日の進み']")
      expect(status).to have_text("365日連続")
      expect(status).to have_text("#{goal_articles * 2 + 2} / #{goal_articles}")
      expect(status.evaluate_script("this.getBoundingClientRect().height")).to be <= 56
      expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
      overflow = status.evaluate_script(<<~JS)
        (() => {
          const link = this.querySelector("a").getBoundingClientRect()
          return Array.from(this.querySelectorAll("a > span:not(.sr-only)")).filter(el => !el.classList.contains("truncate"))
            .some(el => el.getBoundingClientRect().right > link.right + 0.5)
        })()
      JS
      expect(overflow).to be(false), "ステータスの中身がカードの外にはみ出している"
      screenshot!
    end
  end

  it "OGP 画像のある記事は行の右に横長のサムネイルで出し、無い記事・読めない画像は枠ごと出さない" do
    create(:article, title: "画像のある記事", image_url: "/icon.png", published_at: 1.hour.ago)
    create(:article, title: "画像の無い記事", published_at: 2.hours.ago)
    create(:article, title: "画像が消えた記事", image_url: "/missing-og.png", published_at: 3.hours.ago)
    sign_in

    within("article", text: "画像のある記事") do
      image = find("figure img", visible: :all)
      expect(image[:src]).to end_with("/icon.png")
      expect(image[:referrerpolicy]).to eq("no-referrer")
      expect(image[:loading]).to eq("lazy")
      expect(image[:draggable]).to eq("false")
      # 見出しの右に置く
      expect(page.evaluate_script("document.querySelector('article figure').getBoundingClientRect().left > document.querySelector('article h2').getBoundingClientRect().right")).to be(true)
    end
    within("article", text: "画像の無い記事") { expect(page).to have_no_css("figure") }
    within("article", text: "画像が消えた記事") { expect(page).to have_no_css("figure") }
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "横スクロールが出ている"
    screenshot!

    # 画像の真ん中に触れて左へ引くと、画像ではなく行がポインタを受けて「興味なし」になる（iPhone で画像の上から引いても切れない）
    touched = page.evaluate_script(<<~JS)
      (() => {
      const rect = document.querySelector("article figure img").getBoundingClientRect()
      const y = rect.top + rect.height / 2
      const origin = document.elementFromPoint(rect.left + rect.width * 0.5, y)
      const fire = (type, x) => origin.dispatchEvent(new PointerEvent(type, {
        bubbles: true, cancelable: true, composed: true, pointerId: 7, pointerType: "touch", isPrimary: true,
        button: type === "pointermove" ? -1 : 0, buttons: 1, clientX: x, clientY: y
      }))
      fire("pointerdown", rect.left + rect.width * 0.5)
      for (let i = 1; i <= 4; i++) fire("pointermove", rect.left + rect.width * 0.5 - 60 * i)
      fire("pointerup", rect.left + rect.width * 0.5 - 240)
      return origin.tagName
      })()
    JS
    expect(touched).not_to eq("IMG"), "画像がポインタを受けている（iPhone では画像のドラッグや長押しでスワイプが切れる）"
    expect(page).to have_button("元に戻す")
    expect(Article.find_by(title: "画像のある記事")).to be_dismissed
  end

  it "画面の外の行の画像は、読みに行く前に枠を外さず、スクロールして見えたら読む" do
    feed = create(:feed)
    12.times { |i| create(:article, feed: feed, title: "上の記事 #{i}", published_at: 1.hour.ago - i.minutes) }
    create(:article, feed: feed, title: "下の画像の記事", image_url: "/icon.png", published_at: 1.day.ago)
    sign_in

    card = find("article", text: "下の画像の記事")
    expect(card.evaluate_script("this.getBoundingClientRect().top > window.innerHeight")).to be(true), "行が画面内にある（例の前提が崩れた）"
    expect(card).to have_css("figure img", visible: :all)

    card.scroll_to(card, align: :center)
    expect(card).to have_css("figure img", visible: :all)
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.05 until card.find("figure img", visible: :all).evaluate_script("this.complete && this.naturalWidth > 0")
    end
  end

  it "未読 0 本なら空状態が出る" do
    create(:article, :read)
    sign_in

    expect(page).to have_text("全部読んだ。")
    expect(page).to have_text("次の記事が届くまで、今日はここまで。")
    expect(page).to have_no_css("article")
  end

  it "設定からサインアウトするとログイン画面へ" do
    sign_in

    click_on "設定"
    expect(page).to have_css("h1", text: "設定")

    click_on "サインアウト"
    expect(page).to have_current_path(new_session_path)
  end
end
