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

  # bin/ci の最終段「Tests: Seeds」（db:seed:replant）が test DB に seed を残す。fixtures と違って RSpec は
  # テーブルを空にしないので、suite の最初に全部消して「空の DB から始まる」前提を守る
  config.before(:suite) do
    connection = ActiveRecord::Base.connection
    connection.truncate_tables(*(connection.tables - %w[schema_migrations ar_internal_metadata]))
  end
  # rate_limit の回数は Rails.cache に数える。前の例の回数を持ち越さない
  config.before { Rails.cache.clear }
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ActiveJob::TestHelper, type: :job
  config.include ActiveJob::TestHelper, type: :request
  config.include ActiveJob::TestHelper, file_path: %r{spec/services/}
end
