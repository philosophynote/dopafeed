RSpec.describe "Personas", type: :system do
  let(:comments) { { personas_shown: 3, model: "grok-4.3", max_tokens: 4000, timeout_seconds: 60, stream_interval_ms: 250 } }

  before do
    seed_personas
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(comments: comments))
  end

  def menu_of(name)
    find("summary[aria-label='「#{name}」の操作']")
  end

  def menu_open?(name)
    page.evaluate_script("arguments[0].closest('details').open", menu_of(name))
  end

  def row_of(name)
    find("[data-persona]", text: name)
  end

  def focused_label
    page.evaluate_script("document.activeElement.getAttribute('aria-label')")
  end

  def visible_targets_are_44px
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('a, button, summary, input:not([type=hidden]), textarea'))
        .filter(e => e.checkVisibility())
        .every(e => { const r = e.getBoundingClientRect(); return r.width >= 44 && r.height >= 44 })
    JS
  end

  it "行には ⋯ だけを出し、「オフにする」は再読込せずに外して残り、2 行続けても外れ、「オンにする」で戻る。390×844 で収まる" do
    sign_in
    visit learning_path
    click_on "コメントの人物"

    expect(page).to have_css("h1", text: "コメントの人物")
    expect(page).to have_css("[data-persona]", count: 8)
    expect(page).to have_text("有効 8 人。コメントでは 8 人の中から 3 人が出ます")
    expect(page).to have_no_link("変更", visible: true)
    expect(page).to have_no_button("オフにする", visible: true)
    expect(page).to have_no_css("[data-persona-off]")
    expect(viewport_width).to eq(390)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    expect(visible_targets_are_44px).to be(true)
    screenshot!("list")

    menu_of("織田信長").click
    expect(row_of("織田信長")).to have_link("変更", visible: true).and have_button("オフにする", visible: true)
    expect(visible_targets_are_44px).to be(true)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    screenshot!("menu-open")

    page.execute_script("window.notReloaded = true")
    row_of("織田信長").find_button("オフにする").send_keys(:enter)
    expect(row_of("織田信長")).to have_css("[data-persona-off]", text: "オフ")
    expect(page).to have_text("有効 7 人。コメントでは 7 人の中から 3 人が出ます")
    expect(page.evaluate_script("window.notReloaded")).to be(true)
    expect(menu_open?("織田信長")).to be(false)
    expect(focused_label).to eq("「織田信長」の操作")
    screenshot!("disabled")

    visit personas_path
    expect(row_of("織田信長")).to have_css("[data-persona-off]")
    page.execute_script(<<~JS)
      for (const name of ["ヨシフ・スターリン", "毛沢東"]) {
        document.querySelector(`summary[aria-label="「${name}」の操作"]`).closest("details").querySelector("button").click()
      }
    JS
    expect(row_of("ヨシフ・スターリン")).to have_css("[data-persona-off]")
    expect(row_of("毛沢東")).to have_css("[data-persona-off]")
    expect(page).to have_text("有効 5 人")
    expect(Persona.where(slug: %w[joseph-stalin mao-zedong]).pluck(:enabled)).to eq([ false, false ])

    native_click(menu_of("織田信長"))
    expect(row_of("織田信長")).to have_no_button("オフにする", visible: :all)
    native_click(row_of("織田信長").find_button("オンにする"))
    expect(row_of("織田信長")).to have_no_css("[data-persona-off]")
    expect(page).to have_text("有効 6 人")
    expect(focused_label).to eq("「織田信長」の操作")
    expect(Persona.find_by!(slug: "oda-nobunaga").enabled).to be(true)
  end

  it "⋯ は外・Esc・もう一度で閉じ、開くのは 1 行だけ。最後の行のメニューも隠れず押せる" do
    sign_in
    visit personas_path

    menu_of("織田信長").click
    native_click(find("h1"))
    expect(menu_open?("織田信長")).to be(false)

    menu_of("織田信長").click
    native_click(menu_of("毛沢東"))
    expect(menu_open?("織田信長")).to be(false)
    expect(menu_open?("毛沢東")).to be(true)
    menu_of("毛沢東").click
    expect(menu_open?("毛沢東")).to be(false)

    menu_of("毛沢東").send_keys(:enter)
    row_of("毛沢東").find_link("変更").send_keys(:escape)
    expect(menu_open?("毛沢東")).to be(false)
    expect(focused_label).to eq("「毛沢東」の操作")

    last = all("[data-persona] h2").last.text
    menu_of(last).click
    page.scroll_to(row_of(last).find("details"), align: :center)
    last_row_items_on_top = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('[data-persona]:last-of-type details[open] :is(a, button)')).map(e => {
        const r = e.getBoundingClientRect()
        return e.contains(document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2))
      })
    JS
    expect(last_row_items_on_top).to eq([ true, true ])
    screenshot!("last-menu-open")
  end

  it "空白の無い長い名前の無効の行でも、390 幅で横にはみ出さず ⋯ が行の内に残る" do
    create(:persona, name: "Supercalifragilisticexpialidocious" * 2, enabled: false)
    sign_in
    visit personas_path

    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    menu_inside_row = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('[data-persona]')).every(row => {
        const r = row.getBoundingClientRect(), m = row.querySelector('summary').getBoundingClientRect()
        return m.left >= r.left && m.right <= r.right
      })
    JS
    expect(menu_inside_row).to be(true)
  end

  it "全員を外すと案内が変わり、記事を広げてもコメントの欄が出ない" do
    Persona.where.not(slug: "oda-nobunaga").update_all(enabled: false)
    create(:article, :awaiting_summary, summary: "・要約", title: "人物のいない記事")
    sign_in
    visit personas_path

    menu_of("織田信長").click
    click_on "オフにする"
    expect(page).to have_text("有効な人物がいないので、記事にコメントの欄は出ません")
    screenshot!("none")

    visit root_path
    expand("人物のいない記事")
    expect(page).to have_text("・要約")
    expect(page).to have_no_css("section[aria-label='コメント']")
  end

  it "⋯ の「変更」から口調を直して保存すると一覧に戻り、新しい名前と紹介が出る。空白だけなら赤字で止まる" do
    sign_in
    visit personas_path
    menu_of("松岡修造").click
    within(row_of("松岡修造")) { click_on "変更" }

    expect(page).to have_field("名前", with: "松岡修造")
    expect(viewport_width).to eq(390)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    expect(page.evaluate_script("Array.from(document.querySelectorAll('a, button, input:not([type=hidden]), textarea')).every(e => { const r = e.getBoundingClientRect(); return r.width >= 44 && r.height >= 44 })")).to be(true)
    # iOS は 16px 未満の入力欄に触れると拡大する
    expect(page.evaluate_script("Array.from(document.querySelectorAll('input:not([type=hidden]), textarea')).every(e => parseFloat(getComputedStyle(e).fontSize) >= 16)")).to be(true)
    screenshot!("edit")

    fill_in "ひとこと紹介", with: " "
    click_on "保存"
    expect(page).to have_css("[role=alert]", text: "ひとこと紹介を入力してください")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    screenshot!("error")

    find_field("色", type: "color").set("#112233")
    fill_in "肩書き", with: "https://example.com/" + "very-long-title" * 8
    fill_in "ひとこと紹介", with: "とにかく熱い"
    fill_in "口調の指示（system_prompt）", with: "あなたは熱血の人だ。"
    click_on "保存"

    expect(page).to have_css("h1", text: "コメントの人物")
    expect(page).to have_css("[data-persona]", text: "とにかく熱い")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    expect(Persona.find_by!(slug: "shuzo-matsuoka").color).to eq("#112233")
    expect(Persona.find_by!(slug: "shuzo-matsuoka").system_prompt).to eq("あなたは熱血の人だ。")
  end

  it "一覧の「人物を足す」から書いて保存すると一覧に戻り、最後の行に有効で出る。390×844 で横スクロールと小さいタップ領域がない" do
    sign_in
    visit personas_path
    click_on "人物を足す"

    expect(page).to have_css("h1", text: "人物を足す")
    expect(viewport_width).to eq(390)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    expect(page.evaluate_script("Array.from(document.querySelectorAll('a, button, input:not([type=hidden]), textarea')).every(e => { const r = e.getBoundingClientRect(); return r.width >= 44 && r.height >= 44 })")).to be(true)
    expect(page.evaluate_script("Array.from(document.querySelectorAll('input:not([type=hidden]), textarea')).every(e => parseFloat(getComputedStyle(e).fontSize) >= 16)")).to be(true)

    fill_in "名前", with: "坂本龍馬"
    fill_in "肩書き", with: "土佐の脱藩浪士"
    fill_in "ひとこと紹介", with: "日本を今一度せんたくいたし申し候"
    fill_in "口調の指示（system_prompt）", with: "あなたは坂本龍馬だ。土佐弁で話せ。"
    screenshot!("new")
    click_on "保存"

    expect(page).to have_css("h1", text: "コメントの人物")
    expect(page).to have_css("[data-persona]", count: 9)
    expect(all("[data-persona] h2").last.text).to eq("坂本龍馬")
    expect(row_of("坂本龍馬")).to have_no_css("[data-persona-off]")
    expect(page).to have_text("有効 9 人。コメントでは 9 人の中から 3 人が出ます")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    page.scroll_to(find("[data-persona]", text: "坂本龍馬"), align: :center)
    screenshot!("added")
  end
end
