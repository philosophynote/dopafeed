# ログインとサインアウト。ログイン状態の保持と期限は Authentication concern が持つ
class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "試行が多すぎます。少し待ってからもう一度" }

  def new
  end

  def create
    if user = authenticate(params[:password].to_s)
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "パスワードが違います"
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private

  # メールは送られてこないので、ただ一人のユーザーのメールで照合する（ADR 0005）。
  # 0 人・2 人以上は seed か console の誤りで、ログイン画面を 500 にすると直しに入る手がかりも消えるので、入れないだけにする
  def authenticate(password)
    User.authenticate_by(email_address: User.sole.email_address, password: password)
  rescue ActiveRecord::RecordNotFound, ActiveRecord::SoleRecordExceeded
    nil
  end
end
