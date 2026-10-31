RSpec.describe "Passwords", type: :request do
  let!(:user) { create(:user) }

  it "new が開く" do
    get new_password_path
    expect(response).to have_http_status(:ok)
  end

  it "create でリセットメールが積まれ、new_session に戻る" do
    expect {
      post passwords_path, params: { email_address: user.email_address }
    }.to have_enqueued_mail(PasswordsMailer, :reset).with(user)
    expect(response).to redirect_to(new_session_path)

    follow_redirect!
    expect(response.body).to match(/reset instructions sent/)
  end

  it "知らないユーザーでも同じ文言で戻り、メールは送らない" do
    expect {
      post passwords_path, params: { email_address: "missing-user@example.com" }
    }.not_to have_enqueued_mail
    expect(response).to redirect_to(new_session_path)

    follow_redirect!
    expect(response.body).to match(/reset instructions sent/)
  end

  it "edit が開く" do
    get edit_password_path(user.password_reset_token)
    expect(response).to have_http_status(:ok)
  end

  it "edit の token が無効なら new_password に戻る" do
    get edit_password_path("invalid token")
    expect(response).to redirect_to(new_password_path)

    follow_redirect!
    expect(response.body).to match(/reset link is invalid/)
  end

  it "update でパスワードが変わり、new_session に戻る" do
    expect {
      put password_path(user.password_reset_token), params: { password: "new", password_confirmation: "new" }
    }.to change { user.reload.password_digest }
    expect(response).to redirect_to(new_session_path)

    follow_redirect!
    expect(response.body).to match(/Password has been reset/)
  end

  it "確認が一致しなければ変わらず edit に戻る" do
    token = user.password_reset_token
    expect {
      put password_path(token), params: { password: "no", password_confirmation: "match" }
    }.not_to change { user.reload.password_digest }
    expect(response).to redirect_to(edit_password_path(token))

    follow_redirect!
    expect(response.body).to match(/Passwords did not match/)
  end
end
