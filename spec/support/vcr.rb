# CI で未収録の実通信を許さないよう record: :none にする。API キーはカセットから除く。
# 録り直し: VCR_RECORD=all ANTHROPIC_API_KEY=<実キー> bin/rspec spec/services/claude/summarizer_spec.rb
# localhost は Capybara が使うため素通しにする。
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("spec/vcr_cassettes").to_s
  config.hook_into :webmock
  config.ignore_localhost = true
  config.default_cassette_options = { record: ENV.fetch("VCR_RECORD", "none").to_sym, match_requests_on: %i[method uri] }
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
end
