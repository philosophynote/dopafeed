# Install（docs/screens/install.md）。描画で確かめられる受け入れ条件。standalone の分岐は system spec
RSpec.describe "Install", type: :request do
  def page
    Capybara.string(response.body)
  end

  it "未ログインならログイン画面へ" do
    get install_path
    expect(response).to redirect_to(new_session_path)
  end

  context "ログイン済み" do
    before { sign_in_as(create(:user)) }

    it "手順 3 段・無効の「通知を許可する」・Safari のタブの注記・設定への戻りが出る" do
      get install_path

      expect(response).to have_http_status(:ok)
      expect(page).to have_css("h1", text: "ホーム画面に追加")
      expect(page).to have_link("設定に戻る", href: learning_path)
      expect(page.all("ol[aria-label='手順'] li").map(&:text)).to contain_exactly(
        a_string_including("共有ボタン"), a_string_including("「ホーム画面に追加」"), a_string_including("通知を許可")
      )
      expect(page).to have_button("通知を許可する", disabled: true)
      expect(page).to have_text("Safari のタブのままでは通知もバッジも使えません")
      expect(page).to have_text("届く通知")
    end

    it "アイコンのプレビューに未読数のバッジが出る" do
      create_list(:article, 2)

      get install_path

      expect(page).to have_css("[data-unread-badge]", text: "2")
    end

    it "未読が 0 ならプレビューにバッジを出さない" do
      get install_path

      expect(page).to have_no_css("[data-unread-badge]")
    end
  end
end
