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
      expect(page).to have_text("今日のゴール 3 / #{goal_articles}")
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
    expect(page).to have_css("[role='dialog'][aria-label='ルーレット']")
    expect(Article.where("title LIKE ?", "%その 3 本目%").sole.reading).to be_present
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
