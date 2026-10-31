# Rails.logger を一時的に差し替えて、ログに何が出たかを検証する。
module LoggerHelper
  # @param logger [Logger] 差し替えるロガー（StringIO を包んだものなど）
  # @yield 差し替えた状態で実行する処理
  # @return [Object] ブロックの戻り値
  def with_rails_logger(logger)
    original = Rails.logger
    Rails.logger = logger
    yield
  ensure
    Rails.logger = original
  end
end

RSpec.configure do |config|
  config.include LoggerHelper
end
