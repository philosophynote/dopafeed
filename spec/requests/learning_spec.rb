# Learning の最小版（docs/screens/learning.md 未決 4）。サインアウトと、ホーム画面追加への導線の置き場だけ
RSpec.describe "Learning", type: :request do
  it "未ログインならログイン画面へ" do
    get learning_path
    expect(response).to redirect_to(new_session_path)
  end

  it "設定の見出し・サインアウト・ホーム画面に追加（まだ無効）・Main への戻りが出る" do
    sign_in_as(create(:user))

    get learning_path

    page = Capybara.string(response.body)
    expect(response).to have_http_status(:ok)
    expect(page).to have_css("h1", text: "設定")
    expect(page).to have_button("サインアウト")
    expect(page).to have_css("[aria-disabled=true]", text: "ホーム画面に追加")
    expect(page).to have_link("戻る", href: root_path)
  end
end
