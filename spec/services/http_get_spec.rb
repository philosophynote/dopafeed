# 外部通信は WebMock
RSpec.describe HttpGet do
  let(:url) { "https://fixtures.example.com/page" }

  it "2xx の応答をそのまま返し、User-Agent と渡したヘッダを送る" do
    stub_request(:get, url).to_return(status: 200, body: "ok")

    response = described_class.call(url, headers: { "If-None-Match" => '"v1"' })

    expect(response).to be_a(Net::HTTPSuccess)
    expect(response.body).to eq("ok")
    expect(a_request(:get, url).with(headers: { "User-Agent" => described_class::USER_AGENT, "If-None-Match" => '"v1"' })).to have_been_made
  end

  it "304 もそのまま返す" do
    stub_request(:get, url).to_return(status: 304, body: "")
    expect(described_class.call(url)).to be_a(Net::HTTPNotModified)
  end

  it "絶対・相対の Location を追う" do
    stub_request(:get, url).to_return(status: 301, headers: { "Location" => "/moved" })
    stub_request(:get, "https://fixtures.example.com/moved").to_return(status: 302, headers: { "Location" => "https://fixtures.example.com/final" })
    stub_request(:get, "https://fixtures.example.com/final").to_return(status: 200, body: "final")

    expect(described_class.call(url).body).to eq("final")
  end

  it "リダイレクトが上限を超えたら Error" do
    stub_request(:get, url).to_return(status: 301, headers: { "Location" => url })
    expect { described_class.call(url) }.to raise_error(described_class::Error, "リダイレクトが多すぎます")
  end

  it "Location の無い 3xx と 2xx 以外は HTTP の番号つきで Error" do
    stub_request(:get, url).to_return(status: 301)
    expect { described_class.call(url) }.to raise_error(described_class::Error, "サーバーエラー (HTTP 301)")

    stub_request(:get, url).to_return(status: 503)
    expect { described_class.call(url) }.to raise_error(described_class::Error, "サーバーエラー (HTTP 503)")
  end

  it "接続エラーは例外名つきで Error" do
    stub_request(:get, url).to_timeout
    expect { described_class.call(url) }.to raise_error(described_class::Error, "接続エラー (Net::OpenTimeout)")

    stub_request(:get, url).to_raise(SocketError)
    expect { described_class.call(url) }.to raise_error(described_class::Error, "接続エラー (SocketError)")
  end

  it "http(s) でない URL と壊れた URL は Error" do
    expect { described_class.call("mailto:nao@example.com") }.to raise_error(described_class::Error, "URL が http(s) ではありません")
    expect { described_class.call("https://fixtures.example.com/a b") }.to raise_error(described_class::Error, "接続エラー (URI::InvalidURIError)")
  end
end
