RSpec.describe "Personas", type: :system do
  let(:comments) { { personas_shown: 3, model: "grok-4.3", max_tokens: 4000, timeout_seconds: 60 } }

  before do
    seed_personas
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(comments: comments))
  end

  def switch_of(name)
    find("[role=switch][aria-label='#{name}をコメントに出す']")
  end

  it "設定から開き、スイッチで再読込せずに外し、再読込しても残り、続けて 2 行押しても両方外れ、もう一度押すと戻る。390×844 で横スクロールと小さいタップ領域がない" do
    sign_in
    visit learning_path
    click_on "コメントの人物"

    expect(page).to have_css("h1", text: "コメントの人物")
    expect(page).to have_css("[data-persona]", count: 8)
    expect(page).to have_text("有効 8 人。コメントでは 8 人の中から 3 人が出ます")
    expect(viewport_width).to eq(390)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    expect(page.evaluate_script("Array.from(document.querySelectorAll('a, button')).every(e => { const r = e.getBoundingClientRect(); return r.width >= 44 && r.height >= 44 })")).to be(true)
    screenshot!("list")

    page.execute_script("window.notReloaded = true")
    switch_of("織田信長").send_keys(:space)
    expect(page).to have_css("[role=switch][aria-label='織田信長をコメントに出す'][aria-checked=false]")
    expect(page).to have_text("有効 7 人。コメントでは 7 人の中から 3 人が出ます")
    expect(page.evaluate_script("window.notReloaded")).to be(true)
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')")).to eq("織田信長をコメントに出す")
    screenshot!("disabled")

    visit personas_path
    expect(switch_of("織田信長")["aria-checked"]).to eq("false")
    page.execute_script(<<~JS)
      for (const name of ["ヨシフ・スターリン", "毛沢東"]) document.querySelector(`[aria-label="${name}をコメントに出す"]`).click()
    JS
    expect(page).to have_css("[role=switch][aria-label='ヨシフ・スターリンをコメントに出す'][aria-checked=false]")
    expect(page).to have_css("[role=switch][aria-label='毛沢東をコメントに出す'][aria-checked=false]")
    expect(page).to have_text("有効 5 人")
    expect(Persona.where(slug: %w[joseph-stalin mao-zedong]).pluck(:enabled)).to eq([ false, false ])
    switch_of("織田信長").click
    expect(page).to have_css("[role=switch][aria-label='織田信長をコメントに出す'][aria-checked=true]")
    expect(Persona.find_by!(slug: "oda-nobunaga").enabled).to be(true)
  end

  it "全員を外すと案内が変わり、記事を広げてもコメントの欄が出ない" do
    Persona.where.not(slug: "oda-nobunaga").update_all(enabled: false)
    create(:article, :awaiting_summary, summary: "・要約", title: "人物のいない記事")
    sign_in
    visit personas_path

    switch_of("織田信長").click
    expect(page).to have_text("有効な人物がいないので、記事にコメントの欄は出ません")
    screenshot!("none")

    visit root_path
    expand("人物のいない記事")
    expect(page).to have_text("・要約")
    expect(page).to have_no_css("section[aria-label='コメント']")
  end

  it "行の「書き換える」から口調を直して保存すると一覧に戻り、新しい名前と紹介が出る。空白だけなら赤字で止まる" do
    sign_in
    visit personas_path
    within("[data-persona]", text: "松岡修造") { click_on "書き換える" }

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
    expect(switch_of("坂本龍馬")["aria-checked"]).to eq("true")
    expect(page).to have_text("有効 9 人。コメントでは 9 人の中から 3 人が出ます")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    page.scroll_to(find("[data-persona]", text: "坂本龍馬"), align: :center)
    screenshot!("added")
  end
end
