RSpec.describe "Login", type: :system do
  let!(:user) { create(:user) }

  def height_of(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().height")
  end

  # 書いた属性の値。Capybara の [] は DOM のプロパティを読み、Chrome は autocapitalize の off を none と返すので属性で見る
  def attribute_of(selector, name)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getAttribute(#{name.to_json})")
  end

  it "未ログインで / を開くとログイン画面が出る。入力とボタンは 44px 以上、自動大文字化・自動修正は切れている" do
    visit root_path

    expect(page).to have_current_path(new_session_path)
    expect(page).to have_selector("h1", text: "DopaFeed")
    expect(page).to have_text("自分専用。公開 URL なのでログインが要ります")
    expect(page).to have_text("普段この画面は出ません")
    expect(page).to have_no_field("email_address")

    field = find_field("パスワード")
    expect(field[:type]).to eq("password")
    expect(attribute_of("#password", "autocapitalize")).to eq("off")
    expect(attribute_of("#password", "autocorrect")).to eq("off")
    expect(attribute_of("#password", "spellcheck")).to eq("false")
    expect(height_of("#password")).to be >= 44
    expect(height_of("input[type=submit]")).to be >= 44
  end

  it "誤ったパスワードでは日本語の誤りが出る" do
    visit new_session_path
    fill_in "パスワード", with: "wrong"
    click_on "ログイン"

    expect(page).to have_current_path(new_session_path)
    expect(page).to have_selector("#alert", text: "パスワードが違います")
  end

  it "正しいパスワードで Main に着く" do
    visit new_session_path
    fill_in "パスワード", with: "password"
    click_on "ログイン"

    expect(page).to have_current_path(root_path)
    expect(page).to have_link("設定")
  end
end
