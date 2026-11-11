module LoggerHelper
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
