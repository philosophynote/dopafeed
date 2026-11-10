# 図鑑（GET /collection）。docs/screens/collection.md の受け入れ条件のうち、描画で確かめられるもの。数字はすべて dopamine.yml から
RSpec.describe "Collection", type: :request do
  include ActionView::RecordIdentifier

  let(:settings) { Dopamine.settings }
  let(:threshold) { settings.dig(:read, :complete_after_seconds) }
  let(:reset_hour) { settings.dig(:daily_goal, :reset_hour) }
  let(:common) { Dopamine.base_rarity[:name] }
  let(:rare) { Dopamine.rarity_names.second }
  let(:gold) { Dopamine.top_rarity[:name] }
  # 読書日の正午（reset_hour + 8 時間）
  let(:noon) { Time.zone.local(2026, 11, 6, reset_hour) + 8.hours }

  def page
    Capybara.string(response.body)
  end

  # 完読のカードを 1 枚。opened_at から 4 分で読み終えた
  def card(title:, completed_at:, tier: common, **attrs)
    article = create(:article, title: title, **attrs)
    create(:reading, article: article, tier: tier, opened_at: completed_at - 4.minutes, returned_at: completed_at, completed_at: completed_at)
  end

  it "未ログインならログイン画面へ" do
    get collection_path
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "0 枚なら「図鑑」「0 枚」と空状態の文言。束は無い" do
      create(:article, title: "未読の記事")

      travel_to(noon) { get collection_path }

      expect(response).to have_http_status(:ok)
      expect(page).to have_css("h1", text: "図鑑")
      expect(page).to have_text("0 枚", normalize_ws: true)
      expect(page).to have_text("まだカードはありません。")
      expect(page).to have_text("記事を #{threshold} 秒以上読むと、その記事がカードになってここに残ります。")
      expect(page).to have_no_css("section[data-day]")
      expect(page).to have_no_text("未読の記事")
    end

    it "完読日ごとの束を新しい日から並べ、今日・昨日はその名で、それより前は月日と曜日。同じ日の中は完読の新しい順" do
      card(title: "今日の先", completed_at: noon - 2.hours)
      card(title: "今日の後", completed_at: noon - 1.hour)
      card(title: "昨日の 1 枚", completed_at: noon - 1.day)
      card(title: "3 日前の 1 枚", completed_at: noon - 3.days)

      travel_to(noon) { get collection_path }

      expect(page.all("section[data-day] h2").map(&:text)).to eq([ "今日", "昨日", "11月3日（火）" ])
      today = page.find("section[data-day='#{ReadingDay.of(noon)}']")
      expect(today.all("li[data-tier] h3").map(&:text)).to eq([ "今日の後", "今日の先" ])
    end

    it "reset_hour の手前に完読したカードは前日の束に入る" do
      card(title: "夜更かしの 1 枚", completed_at: Time.zone.local(2026, 11, 6, reset_hour) - 1.hour)

      travel_to(noon) { get collection_path }

      expect(page.find("section[data-day='#{ReadingDay.of(noon) - 1}']")).to have_text("夜更かしの 1 枚")
      expect(page).to have_css("section[data-day] h2", text: "昨日")
    end

    it "枚数と内訳を出し、金は金の枠と「金」のラベル、レアは橙の枠と「レア」、通常にはラベルが無い" do
      3.times { |i| card(title: "通常 #{i}", completed_at: noon - (i + 1).hours) }
      rare_card = card(title: "レアの記事", completed_at: noon - 5.hours, tier: rare)
      gold_card = card(title: "金の記事", completed_at: noon - 6.hours, tier: gold)

      travel_to(noon) { get collection_path }

      expect(page).to have_text("5 枚", normalize_ws: true)
      expect(page).to have_text("通常 3 ・ レア 1 ・ 金 1", normalize_ws: true)
      expect(page.find("[role='group'][aria-label='内訳']")).to have_text("1 日連続", normalize_ws: true)
      expect(page).to have_css("li[data-tier='#{gold}']##{dom_id(gold_card, :card)}.border-amber-400", text: "金 金の記事", normalize_ws: true)
      expect(page).to have_css("li[data-tier='#{rare}']##{dom_id(rare_card, :card)}.border-orange-500", text: "レア レアの記事", normalize_ws: true)
      expect(page).to have_css("li[data-tier='#{common}']", count: 3)
      expect(page.find("li[data-tier='#{common}']", text: "通常 0")).to have_no_css("[data-rarity-label]")
      expect(page).to have_no_css("li.card-reveal") # 図鑑では並べて見るだけで、めくらない
    end

    it "未完の行と未読の記事はカードにならない" do
      create(:article, :opened, title: "開いただけ")
      create(:article, title: "未読")
      create(:reading, article: create(:article, title: "未完で戻った"), opened_at: noon - 1.minute, returned_at: noon - 50.seconds)
      card(title: "完読", completed_at: noon - 1.hour)

      travel_to(noon) { get collection_path }

      expect(page.all("li[data-tier] h3").map(&:text)).to eq([ "完読" ])
      expect(page).to have_text("1 枚", normalize_ws: true)
    end

    it "OGP 画像のある記事は画像を表にし、無い記事はフィードの色地。どちらも元記事を別窓で開くリンク" do
      with = card(title: "画像あり", completed_at: noon - 1.hour, image_url: "https://img.example.com/a.png", url: "https://example.com/a")
      without = card(title: "画像なし", completed_at: noon - 2.hours, url: "https://example.com/b")

      travel_to(noon) { get collection_path }

      with_card = page.find("##{dom_id(with, :card)}")
      expect(with_card).to have_css("figure[data-controller='image-fallback'] img[src='https://img.example.com/a.png'][referrerpolicy='no-referrer'][loading='lazy'][data-action='error->image-fallback#remove']")
      without_card = page.find("##{dom_id(without, :card)}")
      expect(without_card).to have_no_css("img")
      expect(without_card.find(".card-face")["class"]).to match(/\bbg-/) # 色地は面（回る箱の li には置かない）
      [ [ with_card, "https://example.com/a", "画像あり" ], [ without_card, "https://example.com/b", "画像なし" ] ].each do |element, href, title|
        link = element.find_link(href: href)
        expect(link[:target]).to eq("_blank")
        expect(link[:rel]).to include("noopener")
        expect(link).to have_text(title)
      end
    end

    it "画像の無いカードの色地は同じフィードなら同じ色で、別のフィードと見分けられる" do
      feed_a = create(:feed)
      feed_b = create(:feed)
      a1 = card(title: "A の 1", completed_at: noon - 1.hour, feed: feed_a)
      a2 = card(title: "A の 2", completed_at: noon - 2.hours, feed: feed_a)
      b = card(title: "B の 1", completed_at: noon - 3.hours, feed: feed_b)

      travel_to(noon) { get collection_path }

      tone = ->(reading) { page.find("##{dom_id(reading, :card)} .card-face")["class"][/\bbg-\S+/] }
      expect(tone.call(a1)).to eq(tone.call(a2))
      expect(tone.call(a1)).not_to eq(tone.call(b))
    end

    it "連続日数は昨日まで続いた日数で、束の曜日は日曜と土曜も出る" do
      sunday = Time.zone.local(2026, 11, 1, reset_hour) + 8.hours
      card(title: "日曜", completed_at: sunday)
      card(title: "土曜", completed_at: sunday - 1.day)
      card(title: "昨日", completed_at: noon - 1.day)

      travel_to(noon) { get collection_path }

      expect(page.all("section[data-day] h2").map(&:text)).to eq([ "昨日", "11月1日（日）", "10月31日（土）" ])
      expect(page.find("[role='group'][aria-label='内訳']")).to have_text("1 日連続", normalize_ws: true)
    end

    it "タブバーの「図鑑」が現在地で、「レポート」は無い。フィードの未読バッジは出る" do
      create(:article)

      get collection_path

      nav = page.find("nav[aria-label='タブバー']")
      expect(nav.find_link("図鑑")["aria-current"]).to eq("page")
      expect(nav).to have_no_text("レポート")
      expect(nav).to have_no_css("[aria-disabled=true]")
      expect(nav.find("[data-unread-badge]")).to have_text("1")
    end
  end
end
