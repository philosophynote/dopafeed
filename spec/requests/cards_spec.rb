RSpec.describe "Cards", type: :request do
  let(:names) { Dopamine.rarity_names }
  let(:rare) { Dopamine.rarity(names.second) }

  def page
    Capybara.string(response.body)
  end

  def card(tier:, judged_as: nil, **attrs)
    create(:reading, :completed, tier: tier, article: create(:article, **attrs)).tap do |reading|
      create(:article_judgment, article: reading.article, **scores_for(judged_as)) if judged_as
    end
  end

  it "未ログインならログイン画面へ" do
    get card_path(card(tier: names.first))
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "カードの裏に、カード・段・6 軸のレーダーと点・合計・「記事を開く」が出る" do
      reading = card(tier: rare[:name], judged_as: rare[:name], title: "裏を見る記事", url: "https://example.com/back")

      get card_path(reading)

      expect(response).to have_http_status(:ok)
      expect(page).to have_css("h1", text: "裏を見る記事")
      expect(page).to have_css("li[data-tier='#{rare[:name]}']")
      expect(page.find("li[data-tier]")).to have_no_css("a"), "カードの面はリンクにしない（記事は下のボタンで開く）"
      expect(page).to have_text("#{rare[:min_total]} 点 ・ レアカード", normalize_ws: true)
      points = reading.article.judgment.points
      label = ArticleJudgment::AXES.map { |axis| "#{I18n.t(axis, scope: "judgment.axes", locale: :ja)} #{points[axis]}" }.join("、")
      chart = page.find("svg[role='img'][aria-label='#{label}']")
      expect(chart.all("[data-radar-grid]").size).to eq(ArticleJudgment::LEVELS)
      expect(chart.find("polygon[data-radar-area]")[:points].split.size).to eq(ArticleJudgment::AXES.size)
      expect(chart.all("text").map { |text| text.text(normalize_ws: true) }).to eq(points.map { |axis, point| "#{I18n.t(axis, scope: "judgment.axes", locale: :ja)} #{point}" })
      expect(page).to have_css("figcaption", text: "合計 #{rare[:min_total]} 点")
      link = page.find_link("記事を開く", href: "https://example.com/back")
      expect(link[:target]).to eq("_blank")
      expect(link[:rel]).to include("noopener")
      expect(page.find("nav").find_link("図鑑")[:href]).to eq(collection_path)
      expect(page).to have_link("図鑑へ戻る", href: collection_path)
    end

    it "判定できなかった記事のカードは、図を出さずに理由を出す。判定中のカードは届くのを待つと出す" do
      get card_path(card(tier: names.first))
      expect(page).to have_no_css("svg[role='img']")
      expect(page).to have_text("判定できず ・ ノーマルカード", normalize_ws: true)
      expect(page).to have_text("この記事は判定できなかったので、点はありません。")

      get card_path(card(tier: nil))
      expect(page).to have_no_css("svg[role='img']")
      expect(page).to have_text("判定中")
      expect(page).to have_text("判定が届くと、6 軸の点がここに出ます。")
    end

    it "枠と判定の段が食い違うカードは、図に今の境界での段を添える" do
      get card_path(card(tier: names.first, judged_as: rare[:name]))

      expect(page).to have_text("判定できず ・ ノーマルカード", normalize_ws: true)
      expect(page).to have_css("figcaption", text: "合計 #{rare[:min_total]} 点 ・ 今の境界ならレア")
    end

    it "完読していない行（カードになっていない）は 404" do
      get card_path(create(:reading))
      expect(response).to have_http_status(:not_found)
    end
  end
end
