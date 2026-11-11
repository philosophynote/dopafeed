RSpec.describe "Sessions", type: :request do
  let!(:user) { create(:user) }

  def session_cookie_line
    Array(response.headers["set-cookie"]).join("\n").lines.find { |l| l.match?(/\Asession_id=[^;]+;/) }
  end

  def session_cookie_expires
    line = session_cookie_line
    return nil unless line

    Time.httpdate(line[/expires=([^;]+)/i, 1])
  end

  def expect_session_cookie_protected
    expect(session_cookie_line).to match(/;\s*httponly/i)
    expect(session_cookie_line).to match(/;\s*samesite=lax/i)
  end

  it "new が開き、パスワード欄だけでメール欄が無い" do
    get new_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("自分専用。公開 URL なのでログインが要ります")
    expect(response.body).to include('name="password"')
    expect(response.body).not_to include('name="email_address"')
    expect(response.body).not_to include(user.email_address)
  end

  it "キーチェーン用の username 欄は固定の名前で、name が無く送られない" do
    get new_session_path

    username = Nokogiri::HTML(response.body).at_css('input[autocomplete="username"]')
    expect(username).to be_present
    expect(username["value"]).to eq("dopafeed")
    expect(username["name"]).to be_nil
  end

  describe "ログイン" do
    it "パスワードだけで root へ進み、Session が 1 件でき、cookie は最後に使ってから保つ期間で切れる" do
      expect {
        post session_path, params: { password: "password" }
      }.to change(Session, :count).by(1)

      expect(response).to redirect_to(root_path)
      expect(session_cookie_expires).to be_within(1.minute).of(Session::REMEMBER_FOR.from_now)
      expect_session_cookie_protected
    end

    it "ログイン前に開こうとした画面へ戻す" do
      get learning_path
      post session_path, params: { password: "password" }

      expect(response).to redirect_to(learning_url)
    end

    it "誤ったパスワードでは new に戻り、日本語の alert が出て、Session はできない" do
      expect {
        post session_path, params: { password: "wrong" }
      }.not_to change(Session, :count)

      expect(response).to redirect_to(new_session_path)
      expect(cookies[:session_id]).to be_nil
      follow_redirect!
      expect(response.body).to include("パスワードが違います")
    end

    it "ユーザーが 1 人もいなければ 500 にせず、誤りと同じに扱う" do
      User.destroy_all

      post session_path, params: { password: "password" }

      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("パスワードが違います")
    end

    it "ユーザーが 2 人以上いれば、正しいパスワードでも入れない" do
      create(:user)

      expect {
        post session_path, params: { password: "password" }
      }.not_to change(Session, :count)

      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("パスワードが違います")
    end

    it "3 分以内に 10 回送ると、11 回目は rate_limit で new に戻る" do
      10.times { post session_path, params: { password: "wrong" } }

      expect {
        post session_path, params: { password: "password" }
      }.not_to change(Session, :count)

      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("試行が多すぎます")
    end
  end

  describe "ログインの保持" do
    it "最後に使ってから保つ期間を過ぎた Session は、cookie があっても通さない" do
      session = sign_in_as(user)
      session.update_column(:updated_at, (Session::REMEMBER_FOR + 1.day).ago)

      get root_path

      expect(response).to redirect_to(new_session_path)
    end

    it "延ばす間隔より前に使った Session は、触って cookie を出し直す" do
      session = sign_in_as(user)
      session.update_column(:updated_at, (Authentication::REMEMBER_REFRESH_INTERVAL + 1.hour).ago)

      get root_path

      expect(response).to have_http_status(:ok)
      expect(session.reload.updated_at).to be_within(1.minute).of(Time.current)
      expect(session_cookie_expires).to be_within(1.minute).of(Session::REMEMBER_FOR.from_now)
      expect_session_cookie_protected
    end

    it "延ばす間隔の内なら、書き込みも cookie の出し直しもしない" do
      session = sign_in_as(user)
      last_used = 1.minute.ago.change(usec: 0)
      session.update_column(:updated_at, last_used)

      get root_path

      expect(response).to have_http_status(:ok)
      expect(session.reload.updated_at).to eq(last_used)
      expect(session_cookie_expires).to be_nil
    end
  end

  it "サインアウトで Session が消え、/ はログインへ戻る" do
    sign_in_as(user)

    expect { delete session_path }.to change(Session, :count).by(-1)

    expect(response).to redirect_to(new_session_path)
    expect(cookies[:session_id]).to be_empty
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "パスワードリセットの口は無い（メールを送れないので runbook の手順で直す）" do
    get "/passwords/new"

    expect(response).to have_http_status(:not_found)
  end
end
