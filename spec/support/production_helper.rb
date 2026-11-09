# Rails.env だけを production に見せる。DB 接続は test のまま（seed は Rails.env.production? しか見ない）。
module ProductionHelper
  def pretending_production
    original = Rails.env
    Rails.env = "production"
    yield
  ensure
    Rails.env = original
  end
end

RSpec.configure do |config|
  config.include ProductionHelper
end
