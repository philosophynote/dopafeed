# request spec でログイン状態を作る。Authentication concern が signed cookie の session_id を見るので、同じ形で焼く。
module SessionHelper
  # @param user [User] ログインさせるユーザー
  # @return [Session] 作った Session
  def sign_in_as(user)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end

    Current.session
  end

  # 今の Session を消して cookie も捨てる
  # @return [void]
  def sign_out
    Current.session&.destroy!
    cookies.delete("session_id")
  end
end

RSpec.configure do |config|
  config.include SessionHelper, type: :request
end
