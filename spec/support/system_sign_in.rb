# cookie を直接作ると、ログイン画面の故障を見逃すため、ブラウザでログインを通す。
module SystemSignIn
  def sign_in
    user = create(:user)
    visit new_session_path
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    expect(page).to have_current_path(root_path)
    user
  end
end

RSpec.configure do |config|
  config.include SystemSignIn, type: :system
end
