require "application_system_test_case"

# 画面そのものは Unit 5 / 15 で作る。ここは 390×844 の枠とスクショ採取が動くことの疎通だけ
class SmokeTest < ApplicationSystemTestCase
  test "login_page_renders_at_iphone_width" do
    visit root_path

    assert_current_path new_session_path
    assert_selector "h1", text: "Sign in"
    assert_equal 390, page.evaluate_script("window.innerWidth")

    path = screenshot!("form")
    assert_equal SCREENSHOT_DIR.join("smoke_test_login_page_renders_at_iphone_width_form.png").to_s, path.to_s
    assert File.exist?(path)
  end

  test "signing_in_reaches_home" do
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign in"

    assert_current_path root_path
    assert_text "Dopafeed"
  end
end
