# 画面そのものは Unit 5 / 15 で作る。ここは 390×844 の枠とスクショ採取が動くことの疎通だけ
RSpec.describe "Smoke", type: :system do
  it "login page renders at iphone width" do
    visit root_path

    expect(page).to have_current_path(new_session_path)
    expect(page).to have_selector("h1", text: "Sign in")
    expect(page.evaluate_script("window.innerWidth")).to eq(390)

    path = screenshot!("form")
    expect(path.to_s).to eq(SystemScreen::SCREENSHOT_DIR.join("smoke_login_page_renders_at_iphone_width_form.png").to_s)
    expect(File).to exist(path)
  end

  it "signing in reaches home" do
    user = create(:user)

    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password"
    click_on "Sign in"

    expect(page).to have_current_path(root_path)
    expect(page).to have_text("Dopafeed")
  end
end
