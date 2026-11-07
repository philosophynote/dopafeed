class User < ApplicationRecord
  # メールでのパスワードリセットは無い（本番に SMTP が無い。ADR 0005）。使わないリセット用トークンを生やさない
  has_secure_password reset_token: false
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
