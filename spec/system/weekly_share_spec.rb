RSpec.describe "Weekly の画像で共有", type: :system do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }
  let(:noon) { Time.zone.local(2026, 11, 20, reset_hour) + 8.hours }

  before do
    feed = create(:feed, title: "とても長い名前のフィードで画像の幅に収まらないかもしれないもの")
    5.times do |i|
      at = noon - i.days
      create(:reading, article: create(:article, feed: feed), opened_at: at - 6.minutes, returned_at: at, completed_at: at)
    end
    WeeklyComment.create!(week_start: Date.new(2026, 11, 9), body: "長いひとこと。" * 30)
  end

  # 共有シートとダウンロードは headless で開けないので、渡されたファイルを記録する
  def stub_share(supported:, error: nil)
    page.execute_script(<<~JS, supported, error)
      window.__shared = null
      window.__downloaded = null
      window.__settled = false
      const [supported, error] = arguments
      navigator.canShare = supported ? () => true : undefined
      navigator.share = async ({ files }) => {
        window.__offered = files[0]
        if (error) throw new DOMException("stub", error)
        window.__shared = files[0]
      }
      HTMLAnchorElement.prototype.click = function () { window.__downloaded = this.download }
      URL.createObjectURL = (file) => { window.__shared = file; return "blob:stub" }
    JS
  end

  def shared_image
    page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      const wait = () => {
        const file = window.__shared
        if (!file) return setTimeout(wait, 50)
        createImageBitmap(file).then((bitmap) => done([file.name, file.type, bitmap.width, bitmap.height, window.__downloaded || null]))
      }
      wait()
    JS
  end

  it "共有できる端末では 1080×1350 の PNG を共有シートに渡す。ボタンは 44px 以上で、横スクロールが無い" do
    travel_to(noon) do
      sign_in
      visit weekly_path
      stub_share(supported: true)

      button = find("button", text: "画像で共有")
      expect(button.native.rect.height).to be >= 44
      button.click

      expect(shared_image).to eq([ "dopafeed-weekly-2026-11-16.png", "image/png", 1080, 1350, nil ])
      expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
      screenshot!("button")
    end
  end

  it "共有できない端末では同じ PNG を保存させる" do
    travel_to(noon) do
      sign_in
      visit weekly_path
      stub_share(supported: false)

      click_button "画像で共有"

      expect(shared_image).to eq([ "dopafeed-weekly-2026-11-16.png", "image/png", 1080, 1350, "dopafeed-weekly-2026-11-16.png" ])
    end
  end

  it "共有シートを閉じただけなら保存させず、ボタンはまた押せる" do
    travel_to(noon) do
      sign_in
      visit weekly_path
      stub_share(supported: true, error: "AbortError")

      click_button "画像で共有"

      expect(page).to have_button("画像で共有", disabled: false)
      expect(page.evaluate_script("[!!window.__offered, window.__shared, window.__downloaded]")).to eq([ true, nil, nil ])
    end
  end

  it "共有シートを開けなかった（NotAllowedError）ときは、作った PNG を保存させる" do
    travel_to(noon) do
      sign_in
      visit weekly_path
      stub_share(supported: true, error: "NotAllowedError")

      click_button "画像で共有"

      expect(shared_image).to eq([ "dopafeed-weekly-2026-11-16.png", "image/png", 1080, 1350, "dopafeed-weekly-2026-11-16.png" ])
      expect(page).to have_button("画像で共有", disabled: false)
    end
  end

  it "フィード名が数万字あっても、表示した後に画像を作り終えて共有できる" do
    huge = create(:feed, title: "あ" * 50_000)
    6.times do |i|
      at = noon - i.hours
      create(:reading, article: create(:article, feed: huge), opened_at: at - 6.minutes, returned_at: at, completed_at: at)
    end

    travel_to(noon) do
      sign_in
      visit weekly_path
      stub_share(supported: true)

      click_button "画像で共有"

      expect(shared_image).to eq([ "dopafeed-weekly-2026-11-16.png", "image/png", 1080, 1350, nil ])
    end
  end

  it "共有の途中で離れても、戻るで Weekly に戻ればまた押せる" do
    travel_to(noon) do
      sign_in
      visit weekly_path
      page.execute_script("navigator.canShare = () => true; navigator.share = () => new Promise(() => {})")
      click_button "画像で共有"
      expect(page).to have_button("画像で共有", disabled: true)

      click_link "図鑑へ戻る"
      expect(page).to have_current_path(collection_path)
      expect(page).to have_no_button("画像で共有")
      page.go_back

      expect(page).to have_current_path(weekly_path)

      expect(page).to have_button("画像で共有", disabled: false)
    end
  end
end
