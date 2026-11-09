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

    expect(Net::HTTP).to have_received(:start).with("fixtures.example.com", 443, nil, hash_including(open_timeout: seconds, read_timeout: seconds))
  end

  it "304 もそのまま返す" do
    stub_request(:get, url).to_return(status: 304, body: "")
    expect(described_class.call(url)).to be_a(Net::HTTPNotModified)
  end

  it "絶対・相対の Location を追う" do
    stub_request(:get, url).to_return(status: 301, headers: { "Location" => "/moved" })
    stub_request(:get, "https://fixtures.example.com/moved").to_return(status: 302, headers: { "Location" => "https://fixtures.example.com/final" })
    stub_request(:get, "https://fixtures.example.com/final").to_return(status: 200, body: "final")

    response = described_class.call(url)
    expect(response.body).to eq("final")
    expect(response.final_url).to eq("https://fixtures.example.com/final")
    expect(response.permanent_url).to eq("https://fixtures.example.com/moved")
  end

  describe "恒久移転（permanent_url）" do
    let(:moved) { "https://fixtures.example.com/moved" }
    let(:final) { "https://fixtures.example.com/final" }

    it "301・308 だけで辿った先を返す（相対の Location も絶対 URL にする）" do
      stub_request(:get, url).to_return(status: 301, headers: { "Location" => "/moved" })
      stub_request(:get, moved).to_return(status: 308, headers: { "Location" => final })
      stub_request(:get, final).to_return(status: 200, body: "final")

      expect(described_class.call(url).permanent_url).to eq(final)
    end

    it "302・307 が挟まったら、その手前までを移転先にする（一時的な寄り道の先は覚えない）" do
      stub_request(:get, url).to_return(status: 301, headers: { "Location" => moved })
      stub_request(:get, moved).to_return(status: 302, headers: { "Location" => final })
      stub_request(:get, final).to_return(status: 200, body: "final")

      expect(described_class.call(url).permanent_url).to eq(moved)
    end

    it "最初が 302・307 なら、後に 301 が続いても移転ではない" do
      stub_request(:get, url).to_return(status: 307, headers: { "Location" => moved })
      stub_request(:get, moved).to_return(status: 301, headers: { "Location" => final })
      stub_request(:get, final).to_return(status: 200, body: "final")

      expect(described_class.call(url).permanent_url).to be_nil
    end

    it "ホストを小文字にしてフラグメントを落とす" do
      stub_request(:get, url).to_return(status: 301, headers: { "Location" => "HTTPS://Fixtures.Example.com/moved#top" })
      stub_request(:get, moved).to_return(status: 200, body: "ok")

      expect(described_class.call(url).permanent_url).to eq(moved)
    end

    it "移転先の 304 でも返す" do
      stub_request(:get, url).to_return(status: 301, headers: { "Location" => moved })
      stub_request(:get, moved).to_return(status: 304, body: "")

      expect(described_class.call(url).permanent_url).to eq(moved)
    end

    it "リダイレクトが無ければ nil" do
      stub_request(:get, url).to_return(status: 200, body: "ok")
      expect(described_class.call(url).permanent_url).to be_nil
    end
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
    it "IP リテラルがループバック・プライベート・リンクローカル・未指定・共有・マルチキャスト・予約帯なら取りに行かず Error" do
      %w[127.0.0.1 10.0.0.1 172.16.0.1 192.168.1.1 169.254.169.254 0.0.0.0 100.64.0.1 192.0.0.1 198.18.0.1 224.0.0.1 240.0.0.1 255.255.255.255
         [::] [::1] [fe80::1] [fc00::1] [ff02::1] [::ffff:127.0.0.1] [::7f00:1]
         [2002:7f00:1::] [2002:a00:1::1] [64:ff9b::a9fe:a9fe] [64:ff9b::7f00:1] [64:ff9b:1::1] [2001::1]].each do |host|
        expect { described_class.call("http://#{host}/latest/meta-data/") }.to raise_error(described_class::Error, "内部ネットワークの URL です") { |e| expect(e).not_to be_a(described_class::TransientError) }
      end
      expect(a_request(:get, /./)).not_to have_been_made
    end

    it "6to4・NAT64 は埋め込まれた IPv4 で判定し、外部の IPv4 なら取りに行く" do
      stub_request(:get, "http://[2002:cb00:710a::]/").to_return(status: 200, body: "6to4")
      stub_request(:get, "http://[64:ff9b::cb00:710a]/").to_return(status: 200, body: "nat64")

      expect(described_class.call("http://[2002:cb00:710a::]/").body).to eq("6to4")
      expect(described_class.call("http://[64:ff9b::cb00:710a]/").body).to eq("nat64")
    end

    it "取りに行かない宛先の検査（verify_external!）も埋め込まれた IPv4 で判定する" do
      expect { described_class.verify_external!("https://[2002:a9fe:a9fe::]/push") }.to raise_error(described_class::Error, "内部ネットワークの URL です")
      expect(described_class.verify_external!("https://[2002:cb00:710a::]/push")).to be_nil
    end

    it "名前が 6to4 で内部アドレスに化けるなら Error" do
      allow(Resolv).to receive(:getaddresses).with("evil.example.com").and_return([ "2002:7f00:1::" ])
      expect { described_class.call("http://evil.example.com/") }.to raise_error(described_class::Error, "内部ネットワークの URL です")
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

    it "名前が引けなければ TransientError、ホスト名が無ければ Error（待っても通らない）" do
      allow(Resolv).to receive(:getaddresses).with("gone.example.com").and_return([])
      expect { described_class.call("https://gone.example.com/") }.to raise_error(described_class::TransientError, "接続エラー (Resolv::ResolvError)")

      expect { described_class.call("http:///x") }.to raise_error(described_class::Error, "URL にホスト名がありません") { |e| expect(e).not_to be_a(described_class::TransientError) }
    end

    it "名前解決の全体を fetch.timeout_seconds で切り、切れたら TransientError" do
      seconds = Dopamine.settings.dig(:fetch, :timeout_seconds)
      allow(Timeout).to receive(:timeout).and_call_original
      stub_request(:get, url).to_return(status: 200, body: "ok")

      described_class.call(url)
      expect(Timeout).to have_received(:timeout).with(seconds, Resolv::ResolvTimeout)

      allow(Resolv).to receive(:getaddresses).and_raise(Resolv::ResolvTimeout)
      expect { described_class.call(url) }.to raise_error(described_class::TransientError, "接続エラー (Resolv::ResolvTimeout)")
    end

    it "解いた IP に接続し、TLS の検証とヘッダはホスト名のまま" do
      stub_request(:get, url).to_return(status: 200, body: "ok")
      allow(Net::HTTP).to receive(:start).and_call_original

      described_class.call(url)

      expect(Net::HTTP).to have_received(:start).with("fixtures.example.com", 443, nil, hash_including(ipaddr: "203.0.113.10", use_ssl: true))
    end

    it "http_proxy 環境変数があってもプロキシを通さない（通すとプロキシが名前を引き直し、検査した IP に繋がらない）" do
      stub_request(:get, url).to_return(status: 200, body: "ok")
      proxied = []
      allow(Net::HTTP).to receive(:new).and_wrap_original { |original, *args| original.call(*args).tap { |http| proxied << http.proxy? } }

      with_env("http_proxy" => "http://proxy.example.com:8080", "https_proxy" => "http://proxy.example.com:8080",
               "HTTP_PROXY" => nil, "HTTPS_PROXY" => nil, "no_proxy" => nil, "NO_PROXY" => nil) do
        described_class.call(url)
      end

      expect(proxied).to eq([ false ])
    end
  end

  it "呼ぶ側の Accept-Encoding は ArgumentError で、取りに行かない（渡すと net-http が展開をやめ、本文の上限が圧縮後で数えられる）" do
    stub_request(:get, url)

    expect { described_class.call(url, headers: { "accept-encoding" => "gzip" }) }.to raise_error(ArgumentError)
    expect { described_class.call(url, headers: { "Accept-Encoding" => "identity" }) }.to raise_error(ArgumentError)
    expect { described_class.call(url, headers: { "accept-encoding": "gzip" }) }.to raise_error(ArgumentError)
    expect(a_request(:get, url)).not_to have_been_made
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

    it "ちょうど上限までは通る。body は String の子で、to_s で素の String になる（呼ぶ側はそれを使う）" do
      stub_request(:get, url).to_return(status: 200, body: "x" * limit)
      body = described_class.call(url).body
      expect(body.bytesize).to eq(limit)
      expect(body).to be_a(String)
      expect(body.to_s.class).to eq(String)
    end

    it "チャンクで届く本文は、足していって上限を超えた時点で Error（WebMock は一度に渡すので直接確かめる）" do
      body = described_class::BoundedBody.new(10, "応答が大きすぎます")
      body << "x" * 4 << "y" * 6
      expect(body).to eq("xxxxyyyyyy")
      expect { body << "z" }.to raise_error(described_class::Error, "応答が大きすぎます")
    end

    it "gzip は展開後の大きさで数える（圧縮爆弾も止まる）" do
      gzipped = ActiveSupport::Gzip.compress("0" * (limit + 1))
      raw = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Encoding: gzip\r\nContent-Length: #{gzipped.bytesize}\r\n\r\n#{gzipped}".b
      response = Net::HTTPResponse.read_new(Net::BufferedIO.new(StringIO.new(raw)))
      response.decode_content = true

      expect(gzipped.bytesize).to be < limit
      expect do
        response.reading_body(Net::BufferedIO.new(StringIO.new(raw.split("\r\n\r\n", 2).last)), true) { response.read_body(described_class::BoundedBody.new(limit, "応答が大きすぎます")) }
      end.to raise_error(described_class::Error, "応答が大きすぎます")
    end
  end

  describe ".verify_external!" do
    it "取りに行かずに宛先だけ検査する。外部なら nil、内部ネットワークなら Error、名前が引けなければ TransientError" do
      expect(described_class.verify_external!("https://push.example.com/sub/1")).to be_nil

      allow(Resolv).to receive(:getaddresses).with("push.example.com").and_return([ "203.0.113.10", "10.0.0.1" ])
      expect { described_class.verify_external!("https://push.example.com/sub/1") }.to raise_error(described_class::Error, "内部ネットワークの URL です") { |e| expect(e).not_to be_a(described_class::TransientError) }
      expect { described_class.verify_external!("https://[::1]/sub/1") }.to raise_error(described_class::Error, "内部ネットワークの URL です")

      allow(Resolv).to receive(:getaddresses).with("gone.example.com").and_return([])
      expect { described_class.verify_external!("https://gone.example.com/") }.to raise_error(described_class::TransientError, "接続エラー (Resolv::ResolvError)")

      expect { described_class.verify_external!("ftp://push.example.com/") }.to raise_error(described_class::Error, "URL が http(s) ではありません")
      expect { described_class.verify_external!("https://push.example.com/a b") }.to raise_error(described_class::Error, "接続エラー (URI::InvalidURIError)")
      expect(a_request(:any, /./)).not_to have_been_made
    end
  end
end
