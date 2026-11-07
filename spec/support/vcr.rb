# Claude API の通信をカセットで再生する。RSS と記事ページは WebMock の stub_request（spec/support/webmock.rb）のまま。
# カセットは spec/vcr_cassettes/。CI は record: :none で、カセットに無い通信は落ちる（実通信ゼロを仕組みで守る）。
# 録り直し: VCR_RECORD=all ANTHROPIC_API_KEY=<実キー> bin/rspec spec/services/claude/summarizer_spec.rb
# API キーはカセットに残らない（x-api-key を <ANTHROPIC_API_KEY> に置き換える）。
# localhost は Capybara（system test の Puma と chromedriver）が使うので VCR も素通しにする
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("spec/vcr_cassettes").to_s
  config.hook_into :webmock
  config.ignore_localhost = true
  config.default_cassette_options = { record: ENV.fetch("VCR_RECORD", "none").to_sym, match_requests_on: %i[method uri] }
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
end
