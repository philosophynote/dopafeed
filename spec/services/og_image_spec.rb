RSpec.describe OgImage do
  let(:base) { URI("https://fixtures.example.com/posts/solid-queue") }

  def html(meta)
    "<html><head>#{meta}<title>t</title></head><body><p>本文</p></body></html>"
  end

  it "og:image の https の URL を返す" do
    expect(described_class.from(html('<meta property="og:image" content=" https://cdn.example.com/og.png ">'), base)).to eq("https://cdn.example.com/og.png")
  end

  it "og:image が無ければ twitter:image（name でも property でも）" do
    expect(described_class.from(html('<meta name="twitter:image" content="https://cdn.example.com/tw.png">'), base)).to eq("https://cdn.example.com/tw.png")
    expect(described_class.from(html('<meta property="twitter:image" content="https://cdn.example.com/tw2.png">'), base)).to eq("https://cdn.example.com/tw2.png")
  end

  it "og:image と twitter:image が両方あれば og:image" do
    meta = '<meta name="twitter:image" content="https://cdn.example.com/tw.png"><meta property="og:image" content="https://cdn.example.com/og.png">'
    expect(described_class.from(html(meta), base)).to eq("https://cdn.example.com/og.png")
  end

  it "og:image:secure_url があればそれを先に" do
    meta = '<meta property="og:image" content="http://cdn.example.com/og.png"><meta property="og:image:secure_url" content="https://cdn.example.com/secure.png">'
    expect(described_class.from(html(meta), base)).to eq("https://cdn.example.com/secure.png")
  end

  it "og:image が使えない（http）なら、次の候補の twitter:image に落ちる" do
    meta = '<meta property="og:image" content="http://cdn.example.com/og.png"><meta name="twitter:image" content="https://cdn.example.com/tw.png">'
    expect(described_class.from(html(meta), base)).to eq("https://cdn.example.com/tw.png")
  end

  it "内部ネットワークの IP を直に書いた URL と userinfo 付きの URL は捨てる" do
    %w[https://127.0.0.1/og.png https://[::1]/og.png https://192.168.1.10/og.png https://[::ffff:10.0.0.1]/og.png https://u:p@cdn.example.com/og.png].each do |url|
      expect(described_class.from(html(%(<meta property="og:image" content="#{url}">)), base)).to be_nil, url
    end
  end

  it "head の後ろ（本文）にある meta は見ない" do
    page = '<html><head><title>t</title></head><body><meta property="og:image" content="https://cdn.example.com/body.png"></body></html>'
    expect(described_class.from(page, base)).to be_nil
  end

  it "相対 URL はページの URL で絶対にする" do
    expect(described_class.from(html('<meta property="og:image" content="/images/og.png">'), base)).to eq("https://fixtures.example.com/images/og.png")
    expect(described_class.from(html('<meta property="og:image" content="//cdn.example.com/og.png">'), base)).to eq("https://cdn.example.com/og.png")
  end

  it "https でなければ捨てる（http・data:・javascript:）" do
    expect(described_class.from(html('<meta property="og:image" content="http://cdn.example.com/og.png">'), base)).to be_nil
    expect(described_class.from(html('<meta property="og:image" content="data:image/png;base64,AAAA">'), base)).to be_nil
    expect(described_class.from(html('<meta property="og:image" content="javascript:alert(1)">'), base)).to be_nil
    expect(described_class.from(html('<meta property="og:image" content="/og.png">'), URI("http://fixtures.example.com/a"))).to be_nil
  end

  it "壊れた URL・空・無いときは nil（生の日本語を含む URL も壊れた URL として捨てる）" do
    expect(described_class.from(html('<meta property="og:image" content="https://例え.jp/画像.png">'), base)).to be_nil
    expect(described_class.from(html('<meta property="og:image" content="https://exa mple.com/ og.png">'), base)).to be_nil
    expect(described_class.from(html('<meta property="og:image" content="">'), base)).to be_nil
    expect(described_class.from(html(""), base)).to be_nil
  end
end
