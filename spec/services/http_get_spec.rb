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

  it "接続・読み取りの待ち時間は dopamine.yml の fetch.timeout_seconds" do
    seconds = Dopamine.settings.dig(:fetch, :timeout_seconds)
    expect(seconds).to be_a(Integer)
    stub_request(:get, url).to_return(status: 200, body: "ok")
    allow(Net::HTTP).to receive(:start).and_call_original

    described_class.call(url)

    expect(Net::HTTP).to have_received(:start).with("fixtures.example.com", 443, hash_including(open_timeout: seconds, read_timeout: seconds))
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

  it "Location の無い 3xx と 4xx は HTTP の番号つきで Error（待っても通らない）" do
    stub_request(:get, url).to_return(status: 301)
    expect { described_class.call(url) }.to raise_error(described_class::Error, "サーバーエラー (HTTP 301)")

    stub_request(:get, url).to_return(status: 404)
    expect { described_class.call(url) }.to raise_error(described_class::Error, "サーバーエラー (HTTP 404)") { |e| expect(e).not_to be_a(described_class::TransientError) }
  end

  it "408・429・5xx は TransientError（待てば通るかもしれない）" do
    %w[408 429 500 503].each do |status|
      stub_request(:get, url).to_return(status: status.to_i)
      expect { described_class.call(url) }.to raise_error(described_class::TransientError, "サーバーエラー (HTTP #{status})")
    end
  end

  it "接続エラーは例外名つきで TransientError" do
    stub_request(:get, url).to_timeout
    expect { described_class.call(url) }.to raise_error(described_class::TransientError, "接続エラー (Net::OpenTimeout)")

    stub_request(:get, url).to_raise(SocketError)
    expect { described_class.call(url) }.to raise_error(described_class::TransientError, "接続エラー (SocketError)")
  end

  it "content_types を渡すと、合わない Content-Type の 2xx は UnexpectedContentType（大文字小文字は無視）" do
    stub_request(:get, url).to_return(status: 200, body: "%PDF", headers: { "Content-Type" => "application/pdf" })
    expect { described_class.call(url, content_types: %w[text/html]) }.to raise_error(described_class::UnexpectedContentType, "application/pdf")

    stub_request(:get, url).to_return(status: 200, body: "<p>ok</p>", headers: { "Content-Type" => "Text/HTML; charset=UTF-8" })
    expect(described_class.call(url, content_types: %w[text/html]).body).to eq("<p>ok</p>")

    stub_request(:get, url).to_return(status: 200, body: "no type")
    expect { described_class.call(url, content_types: %w[text/html]) }.to raise_error(described_class::UnexpectedContentType, "")
  end

  it "http(s) でない URL と壊れた URL は Error（待っても通らない）" do
    expect { described_class.call("mailto:nao@example.com") }.to raise_error(described_class::Error, "URL が http(s) ではありません")
    expect { described_class.call("https://fixtures.example.com/a b") }.to raise_error(described_class::Error, "接続エラー (URI::InvalidURIError)") { |e| expect(e).not_to be_a(described_class::TransientError) }
  end
end
