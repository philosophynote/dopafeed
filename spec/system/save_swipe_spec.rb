# 右スワイプで「保存」（あとで読む）し、Saved で左スワイプで保存を外す（docs/screens/saved.md）。390×844 で通す。引く手は spec/support/system_swipe.rb
RSpec.describe "Save swipe", type: :system do
  let(:now) { Time.current }
  # 左右とも同じ閾値（ADR 0018）。view が yml から Stimulus の value で渡すので、spec も同じ所から読む
  let(:ratio) { Dopamine.settings.dig(:swipe, :dismiss_threshold_ratio) }

  it "右へ引くと左から保存の背景が伸び、閾値を越えて離すと行が消えてトーストが出て未読数が減る。「元に戻す」で行が戻る" do
    create(:article, title: "あとで読む記事", published_at: now - 1.hour)
    create(:article, title: "今読む記事", published_at: now - 2.hours)
    sign_in
    width = card_width("あとで読む記事")
    expect(page).to have_css("[data-unread-badge]", text: "2")

    pull = width * ratio * 0.6
    drag_card("あとで読む記事", from: [ width / 2, 40 ], to: [ width / 2 + pull, 40 ], release: false)
    expect(card_shift("あとで読む記事")).to be > pull * 0.8
    rail = swipe_rail("あとで読む記事", "saveRail")
    expect(rail).to have_css("svg", visible: :all)
    expect(rail).to have_text("保存", normalize_ws: true)
    expect(rail.evaluate_script("this.getBoundingClientRect().width")).to be_within(16).of(pull)
    expect(rail.evaluate_script("this.getBoundingClientRect().left")).to be < width / 4
    expect(rail[:class]).not_to include("swipe-armed")
    # 削除の背景は出ない
    expect(swipe_rail("あとで読む記事").evaluate_script("parseFloat(getComputedStyle(this).opacity)")).to eq(0)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true), "引いている間に横スクロールが出ている"
    screenshot!("pulling")

    # 動いた後のカードの左上から測るので、指の位置は引いた分だけ戻して書く
    drag_card("あとで読む記事", from: [ width / 2, 40 ], to: [ width / 2 + width * ratio * 1.1 - pull, 40 ], release: false, down: false)
    expect(rail[:class]).to include("swipe-armed")
    screenshot!("armed")
    drag_card("あとで読む記事", from: [ width / 2, 40 ], to: [ width / 2 + width * ratio * 0.2, 40 ], down: false)

    expect(find("#toast [data-controller='toast']", text: "1 件を保存しました")).to have_button("元に戻す")
    expect(page).to have_css("article", count: 1)
    expect(page).to have_css("[data-unread-badge]", text: "1")
    expect(Article.find_by(title: "あとで読む記事")).to be_bookmarked
    expect(Article.find_by(title: "あとで読む記事")).not_to be_dismissed
    screenshot!("saved")

    click_on "元に戻す"

    expect(page).to have_css("article", count: 2)
    expect(all("article h2").map(&:text)).to eq(%w[あとで読む記事 今読む記事])
    expect(page).to have_no_css("#toast [data-controller='toast']")
    expect(page).to have_css("[data-unread-badge]", text: "2")
    expect(Article.find_by(title: "あとで読む記事")).not_to be_bookmarked
  end

  it "閾値に届かずに離すと戻り、保存しない" do
    create(:article, title: "迷う記事", published_at: now - 1.hour)
    sign_in
    width = card_width("迷う記事")

    drag_card("迷う記事", from: [ width / 2, 40 ], to: [ width / 2 + width * ratio * 0.5, 40 ])

    expect(settled_shift("迷う記事")).to eq(0)
    expect(swipe_rail("迷う記事", "saveRail").evaluate_script("parseFloat(getComputedStyle(this).opacity)")).to eq(0)
    expect(Article.find_by(title: "迷う記事")).not_to be_bookmarked
  end

  it "Saved の行を左へ引くと保存が外れて行が消えてトーストが出て、保存数が減り Main の未読数が増える。「元に戻す」で行が戻る。右へは動かない" do
    create(:article, title: "取り置いた記事", bookmarked_at: now - 1.hour)
    create(:article, :read, title: "読み終えた記事", bookmarked_at: now - 2.hours)
    sign_in
    find("nav").click_link("保存")
    expect(page).to have_css("h1", text: "保存 (2)")
    width = card_width("取り置いた記事")
    expect(page).to have_no_css("[data-unread-badge]")

    # 右へ引いても動かない（保存の一覧に右の動作は無い）。引いている最中から 0 のまま
    drag_card("取り置いた記事", from: [ width / 2, 40 ], to: [ width / 2 + width * ratio * 1.5, 40 ], release: false)
    expect(card_shift("取り置いた記事")).to eq(0)
    expect(rail_opacity("取り置いた記事")).to eq(0)
    drag_card("取り置いた記事", from: [ width / 2, 40 ], to: [ width / 2, 40 ], steps: 1, down: false)
    expect(settled_shift("取り置いた記事")).to eq(0)
    expect(Article.find_by(title: "取り置いた記事")).to be_bookmarked

    drag_card("取り置いた記事", from: [ width / 2, 40 ], to: [ width / 2 - width * ratio * 0.6, 40 ], release: false)
    rail = swipe_rail("取り置いた記事")
    expect(rail).to have_text("外す", normalize_ws: true)
    screenshot!("pulling")
    drag_card("取り置いた記事", from: [ width / 2, 40 ], to: [ width / 2 - width * ratio * 0.7, 40 ], down: false)

    expect(find("#toast [data-controller='toast']", text: "1 件の保存を外しました")).to have_button("元に戻す")
    expect(page).to have_no_css("article", text: "取り置いた記事")
    expect(page).to have_css("h1", text: "保存 (1)")
    expect(page).to have_css("[data-unread-badge]", text: "1")
    expect(Article.find_by(title: "取り置いた記事")).not_to be_bookmarked
    screenshot!("unsaved")

    click_on "元に戻す"

    expect(page).to have_css("article", count: 2)
    expect(all("article h2").map(&:text)).to eq(%w[取り置いた記事 読み終えた記事])
    expect(page).to have_no_css("#toast [data-controller='toast']")
    expect(page).to have_css("h1", text: "保存 (2)")
    expect(page).to have_no_css("[data-unread-badge]")
    expect(Article.find_by(title: "取り置いた記事")).to be_bookmarked

    # 読んだ行（Reader へのリンク）も引いて外せる。引いた後の click で Reader へ移らない
    drag_card("読み終えた記事", from: [ width / 2, 40 ], to: [ width / 2 - width * ratio * 1.3, 40 ])
    expect(page).to have_css("#toast [data-controller='toast']", text: "1 件の保存を外しました", count: 1)
    expect(page).to have_current_path(saved_path)
    expect(page).to have_css("h1", text: "保存 (1)")
    expect(Article.find_by(title: "読み終えた記事")).not_to be_bookmarked
  end

  it "Saved の読んだ行は、引いて戻した直後の click では Reader へ移らず、次に押せば移る" do
    article = create(:article, :read, title: "読み返す記事", bookmarked_at: now - 1.hour)
    sign_in
    visit saved_path
    width = card_width("読み返す記事")
    link = find("article", text: "読み返す記事").find_link("を開く", visible: :all)

    drag_card("読み返す記事", from: [ width / 2, 40 ], to: [ width / 2 - width * ratio * 0.5, 40 ], on: link)
    expect(settled_shift("読み返す記事")).to eq(0)
    # Turbo がリンクの click を拾うと turbo:click が出る。引いた直後の click はそこまで届かせない
    page.execute_script("window.__visits = 0; document.addEventListener('turbo:click', () => window.__visits++)")
    link.execute_script("this.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 }))")
    expect(page.evaluate_script("window.__visits")).to eq(0)
    expect(page).to have_current_path(saved_path)

    expect(link["draggable"]).to eq("false")
    link.click
    expect(page).to have_current_path(read_article_path(article))
  end
end
