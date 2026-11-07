# ログイン状態を cookie の session_id と Session 行で保ち、使い続ける間は期限を延ばす。期限の長さは Session、ログイン画面の出入りは SessionsController が持つ
module Authentication
  extend ActiveSupport::Concern

  # 使い続けている間は期限（Session::REMEMBER_FOR）を延ばす。毎リクエストの書き込みを避け、この間隔に一度だけ延ばす
  REMEMBER_REFRESH_INTERVAL = 1.day

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie&.tap { |session| extend_session(session) }
    end

    def find_session_by_cookie
      Session.unexpired.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def extend_session(session)
      return if session.updated_at > REMEMBER_REFRESH_INTERVAL.ago

      session.touch
      write_session_cookie(session)
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        write_session_cookie(session)
      end
    end

    def write_session_cookie(session)
      cookies.signed[:session_id] = { value: session.id, httponly: true, same_site: :lax, expires: Session::REMEMBER_FOR.from_now }
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
