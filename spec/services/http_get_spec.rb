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

  describe "内部ネットワークの宛先" do
    it "IP リテラルがループバック・プライベート・リンクローカル・未指定・共有・マルチキャストなら取りに行かず Error" do
      %w[127.0.0.1 10.0.0.1 172.16.0.1 192.168.1.1 169.254.169.254 0.0.0.0 100.64.0.1 224.0.0.1 [::1] [fe80::1] [fc00::1] [::ffff:127.0.0.1]].each do |host|
        expect { described_class.call("http://#{host}/latest/meta-data/") }.to raise_error(described_class::Error, "内部ネットワークの URL です") { |e| expect(e).not_to be_a(described_class::TransientError) }
      end
      expect(a_request(:get, /./)).not_to have_been_made
    end

    it "名前が内部アドレスに解けても Error（解けた全アドレスを見る）" do
      allow(Resolv).to receive(:getaddresses).with("evil.example.com").and_return([ "203.0.113.10", "169.254.169.254" ])
      stub_request(:get, "http://evil.example.com/")

      expect { described_class.call("http://evil.example.com/") }.to raise_error(described_class::Error, "内部ネットワークの URL です")
      expect(a_request(:get, "http://evil.example.com/")).not_to have_been_made
    end

    it "localhost も塞ぐ" do
      allow(Resolv).to receive(:getaddresses).with("localhost").and_return([ "127.0.0.1" ])
      expect { described_class.call("http://localhost:3000/") }.to raise_error(described_class::Error, "内部ネットワークの URL です")
    end

    it "リダイレクト先が内部アドレスでも Error" do
      stub_request(:get, url).to_return(status: 302, headers: { "Location" => "http://169.254.169.254/latest/meta-data/" })
      expect { described_class.call(url) }.to raise_error(described_class::Error, "内部ネットワークの URL です")
    end

    it "名前が引けなければ TransientError" do
      allow(Resolv).to receive(:getaddresses).with("gone.example.com").and_return([])
      expect { described_class.call("https://gone.example.com/") }.to raise_error(described_class::TransientError, "接続エラー (Resolv::ResolvError)")
    end

    it "解いた IP に接続し、TLS の検証とヘッダはホスト名のまま" do
      stub_request(:get, url).to_return(status: 200, body: "ok")
      allow(Net::HTTP).to receive(:start).and_call_original

      described_class.call(url)

      expect(Net::HTTP).to have_received(:start).with("fixtures.example.com", 443, hash_including(ipaddr: "203.0.113.10", use_ssl: true))
    end
  end

  describe "本文サイズの上限" do
    let(:limit) { Dopamine.settings.dig(:fetch, :max_body_megabytes) * 1024 * 1024 }

    it "上限は dopamine.yml の fetch.max_body_megabytes" do
      expect(Dopamine.settings.dig(:fetch, :max_body_megabytes)).to be_a(Integer)
    end

    it "Content-Length が上限を超えていたら本文を読まずに Error" do
      stub_request(:get, url).to_return(status: 200, body: "x", headers: { "Content-Length" => (limit + 1).to_s })
      expect { described_class.call(url) }.to raise_error(described_class::Error, "応答が大きすぎます (#{Dopamine.settings.dig(:fetch, :max_body_megabytes)} MB 超)")
    end

    it "Content-Length が無くても、読みながら上限を超えた時点で Error" do
      stub_request(:get, url).to_return(status: 200, body: "x" * (limit + 1))
      expect { described_class.call(url) }.to raise_error(described_class::Error, "応答が大きすぎます (#{Dopamine.settings.dig(:fetch, :max_body_megabytes)} MB 超)")
    end

    it "ちょうど上限までは通り、body は String で返る" do
      stub_request(:get, url).to_return(status: 200, body: "x" * limit)
      body = described_class.call(url).body
      expect(body.bytesize).to eq(limit)
      expect(body.to_s.class).to eq(String)
    end
  end
end
