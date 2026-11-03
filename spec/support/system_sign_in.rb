# システムテストのログイン。request spec の SessionHelper と違い、ブラウザでログイン画面を通る
# （cookie を焼く手は使えないし、ログイン画面が壊れていれば全画面の例が落ちて気づける）
module SystemSignIn
  # @return [User] ログインしたユーザー
  def sign_in
    user = create(:user)
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
    user
  end
end

RSpec.configure do |config|
  config.include SystemSignIn, type: :system
end
