# テスト中の外部通信を止める。CI は実通信ゼロ（AGENTS.md）を規約でなく仕組みで守る。
# localhost は Capybara（system test の Puma と chromedriver）が使うので通す。
# RSS は WebMock の stub_request + spec/fixtures/files/feeds/*.xml、Claude API は VCR（Unit 4）
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)
