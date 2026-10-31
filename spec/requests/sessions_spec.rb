RSpec.describe "Sessions", type: :request do
  let!(:user) { create(:user) }

  it "new が開く" do
    get new_session_path
    expect(response).to have_http_status(:ok)
  end

  it "正しい資格情報で create すると root へ進み、cookie に session_id が付く" do
    post session_path, params: { email_address: user.email_address, password: "password" }

    expect(response).to redirect_to(root_path)
    expect(cookies[:session_id]).to be_present
  end

  it "誤った資格情報では new に戻り、cookie は付かない" do
    post session_path, params: { email_address: user.email_address, password: "wrong" }

    expect(response).to redirect_to(new_session_path)
    expect(cookies[:session_id]).to be_nil
  end

  it "destroy で new に戻り、cookie が空になる" do
    sign_in_as(user)

    delete session_path

    expect(response).to redirect_to(new_session_path)
    expect(cookies[:session_id]).to be_empty
  end
end
