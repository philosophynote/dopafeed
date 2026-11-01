RSpec.describe "Home", type: :request do
  it "未ログインなら root はログイン画面へ" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "ログイン済みなら root が開く" do
    sign_in_as(create(:user))
    get root_path
    expect(response).to have_http_status(:ok)
  end
end
