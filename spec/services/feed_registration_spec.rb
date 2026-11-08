RSpec.describe FeedRegistration do
  let(:url) { "https://fixtures.example.com/feed.xml" }
  let(:rss) { file_fixture("feeds/rss2.xml").read }

  { "rss2" => "Fixture RSS", "atom" => "Fixture Atom" }.each do |file, title|
    it "#{file} のタイトルで登録し、記事は作らず取得を予約する" do
      stub_request(:get, url).to_return(body: file_fixture("feeds/#{file}.xml").read)
      result = nil
      expect { result = described_class.call(" #{url}#latest ") }.to change(Feed, :count).by(1)
      expect(result.feed).to have_attributes(url: url, title: title)
      expect(Article.count).to eq(0)
      expect(FetchFeedJob).to have_been_enqueued.with(result.feed)
    end
  end

  it "登録済みなら取りに行かず、取得を重ねて予約しない" do
    existing = create(:feed, url: url)
    expect(described_class.call(url).feed).to eq(existing)
    expect(described_class.call(url).message).to eq("登録済み")
    expect(enqueued_jobs).to be_empty
  end

  it "同時登録で一意制約に当たれば登録済みとして扱う" do
    stub_request(:get, url).to_return(body: rss)
    allow(Feed).to receive(:create!).and_wrap_original { |method, **attrs| method.call(**attrs); method.call(**attrs) }
    expect(described_class.call(url).message).to eq("登録済み")
    expect(Feed.count).to eq(1)
    expect(enqueued_jobs).to be_empty
  end

  it "不正な URL・内部宛先・内部へのリダイレクトを登録しない" do
    stub_request(:get, url).to_return(status: 302, headers: { "Location" => "http://127.0.0.1/feed" })
    [ "not a url", "file:///etc/passwd", "http://169.254.169.254/", url ].each do |input|
      expect(described_class.call(input).feed).to be_nil
    end
    expect(Feed.count).to eq(0)
    expect(enqueued_jobs).to be_empty
  end

  it "HTTP エラー・タイムアウト・本文超過・壊れた XML・空タイトルでは登録しない" do
    large = (Dopamine.settings.dig(:fetch, :max_body_megabytes) * 1024 * 1024 + 1).to_s
    [ { status: 503 }, { headers: { "Content-Length" => large } }, { body: "<rss>" }, { body: rss.sub("Fixture RSS", " ") } ].each do |response|
      stub_request(:get, url).to_return(**response)
      expect(described_class.call(url).feed).to be_nil
    end
    stub_request(:get, url).to_timeout
    expect(described_class.call(url).message).to include("接続エラー")
    expect(Feed.count).to eq(0)
    expect(enqueued_jobs).to be_empty
  end

  it "サイトから検出した URL で登録し、登録済みなら候補を再取得・予約しない" do
    site = "https://fixtures.example.com/"
    stub_request(:get, site).to_return(body: '<html><head><link rel="alternate" type="application/rss+xml" href="/feed.xml#latest"></head></html>', headers: { "Content-Type" => "text/html" })
    stub_request(:get, url).to_return(body: rss)
    result = described_class.call(site)
    expect(result.feed).to have_attributes(url: url, title: "Fixture RSS")
    expect(described_class.call(site).message).to eq("登録済み")
    expect(a_request(:get, url)).to have_been_made.once
    expect(enqueued_jobs.size).to eq(1)
  end

  [ false, ActiveRecord::ConnectionNotEstablished ].each do |failure|
    it "取得予約が #{failure || 'false'} でも登録は残し、再試行を案内する" do
    stub_request(:get, url).to_return(body: rss)
    allow(FetchFeedJob).to receive(:perform_later) { raise failure if failure; false }
    result = described_class.call(url)
    expect(result.feed.reload.title).to eq("Fixture RSS")
    expect(result.message).to include("後ほど再試行")
    end
  end
end
