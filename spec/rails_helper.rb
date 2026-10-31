# Rails を読む側の設定。.rspec が --require rails_helper で読むので、各 spec に require は要らない。
# fixtures は使わない（ADR 0007）。レコードは spec/factories の FactoryBot で作る。
ENV["RAILS_ENV"] ||= "test"
require "spec_helper"
require_relative "../config/environment"
abort("production でテストは走らせない") if Rails.env.production?
require "rspec/rails"

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ActiveJob::TestHelper, type: :job
  config.include ActiveJob::TestHelper, type: :request
end
