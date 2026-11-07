RSpec.describe "FeedDiscovery" do
  let(:site) { "https://fixtures.example.com/blog/" }
  let(:rss) { file_fixture("feeds/rss2.xml").read }

  def html(links, type = "text/html")
    stub_request(:get, site).to_return(body: "<html><head>#{links}</head></html>", headers: { "Content-Type" => type })
  end

  def link(href, type = "Application/Rss+Xml; charset=utf-8")
    %(<link rel="other ALTERNATE" type="#{type}" href="#{href}">)
  end

  it "RSS / Atom は Content-Type によらず直接解析する" do
    %w[rss2 atom].each do |file|
      stub_request(:get, site).to_return(body: file_fixture("feeds/#{file}.xml").read)
      expect(FeedDiscovery.call(site).url).to eq(site)
    end
    expect(HttpGet.call(site).final_url).to eq(site)
  end

  it "一時移動も含む最終 URL を基準に、HTML / XHTML の相対・絶対・外部リンクを解決する" do
    [ [ "news.xml", "https://other.example.com:8443/posts/news.xml" ], [ "/feed", "https://other.example.com:8443/feed" ], [ "//cdn.example.com/rss", "https://cdn.example.com/rss" ] ].each do |href, target|
      stub_request(:get, site).to_return(status: 307, headers: { "Location" => "https://other.example.com:8443/posts/" })
      stub_request(:get, "https://other.example.com:8443/posts/").to_return(body: "<html><head><base href='https://ignored.example.com/'>#{link(href, 'application/atom+xml')}</head></html>", headers: { "Content-Type" => "application/xhtml+xml" })
      stub_request(:get, target).to_return(body: rss)
      expect(FeedDiscovery.call(site).url).to eq(target)
    end
  end

  it "無効・重複・自身を除き文書順で試し、最初の成功で止める" do
    html([ "", "http://[", "file:///etc/passwd", site, "/bad", "/bad#again", "/ok", "/unused" ].map { |href| link(href) }.join)
    stub_request(:get, "https://fixtures.example.com/bad").to_return(body: "<rss>")
    stub_request(:get, "https://fixtures.example.com/ok").to_return(body: rss)
    expect(FeedDiscovery.call(site).title).to eq("Fixture RSS")
    expect(a_request(:get, "https://fixtures.example.com/bad")).to have_been_made.once
    expect(a_request(:get, "https://fixtures.example.com/unused")).not_to have_been_made
  end

  it "HTML 候補は 5 件までで、候補 HTML を再探索せずルートの定番パスへ進む" do
    html((1..6).map { |n| link("/candidate#{n}") }.join)
    (1..5).each { |n| stub_request(:get, "https://fixtures.example.com/candidate#{n}").to_return(body: "<html><head>#{link('/nested')}</head></html>") }
    attempts = []
    %w[feed rss atom.xml].each { |path| stub_request(:get, "https://fixtures.example.com/#{path}").to_return { attempts << path; { status: 404 } } }
    stub_request(:get, "https://fixtures.example.com/index.xml").to_return { attempts << "index.xml"; { body: rss } }
    expect(FeedDiscovery.call(site).url).to eq("https://fixtures.example.com/index.xml")
    expect(attempts).to eq(%w[feed rss atom.xml index.xml])
    expect(a_request(:get, %r{/candidate6|/nested|/blog/feed})).not_to have_been_made
  end

  it "定番パスも移動後の origin を使い、HTML 候補との重複を取得し直さない" do
    stub_request(:get, site).to_return(status: 302, headers: { "Location" => "https://other.example.com:8443/posts/" })
    stub_request(:get, "https://other.example.com:8443/posts/").to_return(body: "<html><head>#{link('/feed')}</head></html>", headers: { "Content-Type" => "text/html" })
    stub_request(:get, "https://other.example.com:8443/feed").to_return(status: 404)
    stub_request(:get, "https://other.example.com:8443/rss").to_return(body: rss)
    expect(FeedDiscovery.call(site).url).to eq("https://other.example.com:8443/rss")
    expect(a_request(:get, "https://other.example.com:8443/feed")).to have_been_made.once
  end

  it "誤った rel/type・body 内のリンクを候補にしない" do
    html('<link rel="alternates" type="application/rss+xml" href="/wrong"><link rel="alternate" type="text/html" href="/wrong"></head><body>' + link("/wrong"))
    stub_request(:get, "https://fixtures.example.com/feed").to_return(body: rss)
    expect(FeedDiscovery.call(site).url).to end_with("/feed")
  end

  it "内部 IP・内部解決・内部への移動・大きすぎる本文・空タイトルを飛ばす" do
    html([ "http://127.0.0.1/", "https://internal.example.com/", "/redirect", "/large", "/blank" ].map { |href| link(href) }.join)
    allow(Resolv).to receive(:getaddresses).with("internal.example.com").and_return([ "10.0.0.1" ])
    stub_request(:get, "https://fixtures.example.com/redirect").to_return(status: 302, headers: { "Location" => "http://169.254.169.254/" })
    stub_request(:get, "https://fixtures.example.com/large").to_return(headers: { "Content-Length" => (Dopamine.settings.dig(:fetch, :max_body_megabytes) * 1024 * 1024 + 1).to_s })
    stub_request(:get, "https://fixtures.example.com/blank").to_return(body: rss.sub("Fixture RSS", " "))
    stub_request(:get, "https://fixtures.example.com/feed").to_return(body: rss)
    expect(FeedDiscovery.call(site).title).to eq("Fixture RSS")
    expect(a_request(:get, %r{127\.0\.0\.1|internal\.example|169\.254\.169\.254})).not_to have_been_made
  end

  it "未検出と、一時的な通信失敗で確認できない場合を区別する" do
    html("")
    %w[feed rss atom.xml index.xml].each { |path| stub_request(:get, "https://fixtures.example.com/#{path}").to_return(status: 404) }
    expect { FeedDiscovery.call(site) }.to raise_error(FeedDiscovery::Error, "フィードが見つかりません")
    stub_request(:get, "https://fixtures.example.com/feed").to_timeout
    expect { FeedDiscovery.call(site) }.to raise_error(FeedDiscovery::Error, /時間をおいて/)
  end

  it "入口からの全体制限は専用例外で打ち切り、次の取得や登録へ進まない" do
    html(link("/slow"))
    allow(HttpGet).to receive(:call).and_call_original
    allow(HttpGet).to receive(:call).with("https://fixtures.example.com/slow") { Queue.new.pop }
    allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.deep_merge(fetch: { timeout_seconds: 0.1 }))
    allow(Timeout).to receive(:timeout).and_call_original
    expect(Timeout).to receive(:timeout).with(0.1, FeedDiscovery::Expired).and_call_original
    result = FeedRegistration.call(site)
    expect(result.message).to include("タイムアウト")
    expect(Feed.count).to eq(0)
    expect(enqueued_jobs).to be_empty
    expect(a_request(:get, "https://fixtures.example.com/feed")).not_to have_been_made
  end
end
