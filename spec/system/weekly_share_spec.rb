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
  def stub_share(supported:)
    page.execute_script(<<~JS, supported)
      window.__shared = null
      const supported = arguments[0]
      navigator.canShare = supported ? () => true : undefined
      navigator.share = async ({ files }) => { window.__shared = files[0] }
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
end
