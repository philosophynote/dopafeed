RSpec.describe "Weekly", type: :request do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }
  let(:gold) { Dopamine.top_rarity[:name] }
  # 2026-11-18（水）の正午。今週は 11/16（月）〜 11/22（日）
  let(:noon) { Time.zone.local(2026, 11, 18, reset_hour) + 8.hours }

  def page
    Capybara.string(response.body)
  end

  def complete(completed_at, tier: Dopamine.base_rarity[:name], dwell: 4.minutes, **attrs)
    article = create(:article, **attrs)
    create(:reading, article: article, tier: tier, opened_at: completed_at - dwell, returned_at: completed_at, completed_at: completed_at)
  end

  it "未ログインならログイン画面へ" do
    get weekly_path
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "今週 32 本・先週 23 本なら「32 本」「先週比 +39%（23 本）」と週の範囲、読書時間、カードの内訳、要約の本数、フィード別を出す" do
      zenn = create(:feed, title: "Zenn")
      32.times { |i| complete(noon - i.minutes, dwell: 5.minutes, feed: zenn, tier: i.zero? ? gold : Dopamine.base_rarity[:name]) }
      23.times { complete(noon - 7.days) }

      travel_to(noon) { get weekly_path }

      expect(response).to have_http_status(:ok)
      expect(page).to have_css("h1", text: "今週のレポート")
      expect(page).to have_text("11/16 – 11/22")
      expect(page.find("[aria-label='今週の本数']")).to have_text("32 本 読了 先週比 +39%（23 本）", normalize_ws: true)
      expect(page).to have_text("読書時間 2時間40分", normalize_ws: true)
      expect(page.find("[aria-label='カード']")).to have_text("カード 32 枚 ノーマル 31 ・ レア 0 ・ S レア 0 ・ SS レア 1", normalize_ws: true)
      expect(page).to have_text("ひとこと要約 32 本", normalize_ws: true)
      expect(page.find("[aria-label='フィード別']")).to have_text("Zenn 32", normalize_ws: true)
      expect(page.all("[aria-label='曜日別'] li").map { |li| li["aria-label"] }).to eq(%w[月曜 火曜 水曜 木曜 金曜 土曜 日曜].each_with_index.map { |day, i| "#{day} #{i == 2 ? 32 : 0} 本" })
      expect(page).to have_css("[aria-label='今週の本数'] .text-emerald-700", text: "先週比 +39%")
    end

    it "曜日は今日を橙の字、まだ来ない日を薄い灰の字にする" do
      travel_to(noon) { get weekly_path }

      days = page.all("[aria-label='曜日別'] li")
      expect(days.map { |li| li["data-day-state"] }).to eq(%w[past past today future future future future])
      expect(days[2]).to have_css(".text-orange-600", text: "水")
      expect(days[3]).to have_css(".text-gray-300", text: "木")
    end

    it "判定中のカードがあれば内訳に「判定中 N」を足す" do
      complete(noon - 1.hour, tier: nil)

      travel_to(noon) { get weekly_path }

      expect(page.find("[aria-label='カード']")).to have_text("SS レア 0 ・ 判定中 1", normalize_ws: true)
    end

    it "今週は読んだが先週 0 本なら、Weekly も図鑑の 1 行も先週比を出さず「先週 0 本」" do
      complete(noon - 1.hour)

      travel_to(noon) { get weekly_path }
      expect(page.find("[aria-label='今週の本数']")).to have_text("1 本 読了 先週 0 本", normalize_ws: true)
      expect(page).to have_no_text("先週比")

      travel_to(noon) { get collection_path }
      expect(page.find("a[href='#{weekly_path}']")).to have_text("今週 1 本 ・ 先週 0 本", normalize_ws: true)
    end

    it "今週の読了 0・先週 0 なら 0 本で、先週比は出さず「先週 0 本」。棒は空、フィード別は無い" do
      travel_to(noon) { get weekly_path }

      expect(page.find("[aria-label='今週の本数']")).to have_text("0 本 読了 先週 0 本", normalize_ws: true)
      expect(page).to have_no_text("先週比")
      bars = page.all("[aria-label='曜日別'] li > span:nth-child(2)")
      expect(bars.map { |bar| bar["style"] }).to all(eq("height: 0%"))
      expect(bars.size).to eq(7)
      expect(page).to have_no_css("[aria-label='フィード別']")
      expect(page).to have_text("読書時間 0分", normalize_ws: true)
    end

    it "図鑑の見出しの下に今週の本数と先週比の 1 行があり、Weekly へつながる。Weekly でもタブは図鑑が現在地" do
      complete(noon - 1.hour)
      2.times { complete(noon - 7.days) }

      travel_to(noon) { get collection_path }
      link = page.find("a[href='#{weekly_path}']")
      expect(link).to have_text("今週 1 本 ・ 先週比 -50%", normalize_ws: true)

      travel_to(noon) { get weekly_path }
      expect(page.find("nav").find_link("図鑑")["aria-current"]).to eq("page")
      expect(page).to have_link("図鑑へ戻る", href: collection_path)
    end

    it "先週のひとことがあれば「Claude のひとこと」と先週の範囲を添えて出す。失敗の行・先週より前の行は出さない" do
      WeeklyComment.create!(week_start: Date.new(2026, 11, 2), body: "先々週のひとこと")
      WeeklyComment.create!(week_start: Date.new(2026, 11, 9), body: "先週は Rails を 3 本。来週は設計を 1 本。")

      travel_to(noon) { get weekly_path }

      section = page.find("[aria-label='Claude のひとこと']")
      expect(section).to have_text("11/9 – 11/15 の週", normalize_ws: true)
      expect(section).to have_text("先週は Rails を 3 本。来週は設計を 1 本。")
      expect(page).to have_no_text("先々週のひとこと")
    end

    it "先週のひとことが無い・失敗したなら欄ごと出さない" do
      travel_to(noon) { get weekly_path }
      expect(page).to have_no_css("[aria-label='Claude のひとこと']")

      WeeklyComment.create!(week_start: Date.new(2026, 11, 9), failed_at: noon, error: "接続エラー")
      travel_to(noon) { get weekly_path }
      expect(page).to have_no_css("[aria-label='Claude のひとこと']")
    end

    it "「画像で共有」ボタンが、画像に描く数字とひとことを JSON で持ち、週の始まりの日付をファイル名にする" do
      zenn = create(:feed, title: "Zenn")
      3.times { |i| complete(noon - i.minutes, feed: zenn, dwell: 10.minutes) }
      complete(noon - 7.days)
      WeeklyComment.create!(week_start: Date.new(2026, 11, 9), body: "先週のひとこと")

      travel_to(noon) { get weekly_path }

      button = page.find("button[data-controller='weekly-share']", text: "画像で共有")
      card = JSON.parse(button["data-weekly-share-card-value"])
      expect(button["data-weekly-share-filename-value"]).to eq("dopafeed-weekly-2026-11-16.png")
      expect(card).to include("title" => "今週のレポート", "range" => "11/16 – 11/22", "streak" => "1 日連続", "count" => 3,
                              "change" => "先週比 +200%（1 本）", "up" => true, "footer" => "DopaFeed ・ 過去の自分と比べる週次カード")
      expect(card["days"].map { |day| [ day["label"], day["count"], day["state"] ] }).to eq(
        [ [ "月", 0, "past" ], [ "火", 0, "past" ], [ "水", 3, "today" ], [ "木", 0, "future" ], [ "金", 0, "future" ], [ "土", 0, "future" ], [ "日", 0, "future" ] ]
      )
      expect(card["stats"]).to eq([ [ "読書時間", "30分" ], [ "カード", "3 枚" ], [ "ひとこと要約", "3 本" ], [ "よく読んだフィード", "Zenn", "3" ] ])
      expect(card["comment"]).to eq("label" => "Claude のひとこと ・ 11/9 – 11/15 の週", "body" => "先週のひとこと")
    end

    it "0 本の週はフィードの行とひとことを描かない" do
      travel_to(noon) { get weekly_path }

      card = JSON.parse(page.find("button[data-controller='weekly-share']")["data-weekly-share-card-value"])
      expect(card).to include("count" => 0, "change" => "先週 0 本", "up" => false, "comment" => nil)
      expect(card["stats"].map(&:first)).to eq(%w[読書時間 カード ひとこと要約])
    end
  end
end
