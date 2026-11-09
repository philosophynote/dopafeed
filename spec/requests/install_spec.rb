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

    it "VAPID 鍵があれば公開鍵と購読先を Stimulus に渡し、拒否時の文言も用意する" do
      with_env("VAPID_PUBLIC_KEY" => "BPublic", "VAPID_PRIVATE_KEY" => "private", "VAPID_SUBJECT" => "mailto:nao@example.com") { get install_path }

      install = page.find("[data-controller=install]")
      expect(install["data-install-vapid-public-key-value"]).to eq("BPublic")
      expect(install["data-install-subscribe-url-value"]).to eq(push_subscription_path)
      expect(page).to have_css("[data-install-target=denied]", text: "iPhone の設定から通知を許可してください", visible: :all)
      expect(page).to have_no_text("通知の鍵")
    end

    it "VAPID 鍵が無ければ「サーバーに通知の鍵が無い」と出し、Stimulus に鍵を渡さない" do
      with_env("VAPID_PUBLIC_KEY" => nil, "VAPID_PRIVATE_KEY" => nil, "VAPID_SUBJECT" => nil) { get install_path }

      expect(page).to have_text("サーバーに通知の鍵がありません")
      expect(page.find("[data-controller=install]")["data-install-vapid-public-key-value"]).to be_blank
    end

    it "届く通知の時刻は dopamine.yml の push.digest_at / push.streak_warning_at。鍵が無い間は時刻を出さない" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.except(:push))
      get install_path
      expect(page.find("section[aria-label='届く通知']")).to have_no_text(":")

      # 21:00 は引用符を忘れて書かれた形（YAML の六十進数 = 75600）。それでも 21:00 と出す
      settings = Dopamine.settings.merge(push: { digest_at: "07:30", streak_warning_at: 75_600 })
      allow(Dopamine).to receive(:settings).and_return(settings)
      get install_path
      notices = page.find("section[aria-label='届く通知']")
      expect(notices).to have_text("07:30")
      expect(notices).to have_text("21:00")
    end
  end
end
