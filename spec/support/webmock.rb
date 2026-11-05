# テスト中の外部通信を止める。CI は実通信ゼロ（AGENTS.md）を規約でなく仕組みで守る。
# localhost は Capybara（system test の Puma と chromedriver）が使うので通す。
# RSS は WebMock の stub_request + spec/fixtures/files/feeds/*.xml、Claude API は VCR（Unit 4）
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

# WebMock は HTTP を止めるが DNS は止めない。HttpGet が接続の前に Resolv.new で作るリゾルバで名前を引くので、
# Resolv.new を差し替えて、既定では文書用の公開アドレス（RFC 5737 の 203.0.113.0/24）に解けたことにする。
# 内部アドレスに解ける例は spec ごとに `allow(Resolv.new).to receive(:getaddresses).with(host)` で上書きする
RSpec.configure do |config|
  config.before do
    resolver = instance_double(Resolv)
    allow(resolver).to receive(:getaddresses).and_return([ "203.0.113.10" ])
    allow(Resolv).to receive(:new).and_return(resolver)
  end
end
