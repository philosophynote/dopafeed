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

  it "og:image が複数あれば、使える最初のものを選ぶ" do
    meta = '<meta property="og:image" content="http://cdn.example.com/a.png"><meta property="og:image" content="https://cdn.example.com/b.png">'
    expect(described_class.from(html(meta), base)).to eq("https://cdn.example.com/b.png")
  end

  it "内部ネットワークを直に指す URL（IP・localhost）、ホスト名の形でないもの（% で隠した点・数字の IPv4）、userinfo 付きは捨てる" do
    %w[
      https://127.0.0.1/og.png https://127.0.0.1./og.png https://[::1]/og.png https://192.168.1.10/og.png https://[::ffff:10.0.0.1]/og.png
      https://2130706433/og.png https://0x7f000001/og.png https://127.1/og.png https://0177.0.0.1/og.png https://10.0x1/og.png
      https://127%2e0%2e0%2e1/og.png https://%31%32%37.0.0.1/og.png https://cdn_1.example.com/og.png
      https://localhost/og.png https://app.localhost/og.png https://u:p@cdn.example.com/og.png
    ].each do |url|
      expect(described_class.from(html(%(<meta property="og:image" content="#{url}">)), base)).to be_nil, url
    end
  end

  it "head の後ろ（本文）にある meta は見ない" do
    page = '<html><head><title>t</title></head><body><meta property="og:image" content="https://cdn.example.com/body.png"></body></html>'
    expect(described_class.from(page, base)).to be_nil
  end

  it "普通のホスト名（punycode を含む）と外の IP はそのまま通す" do
    %w[https://cdn1.example.com/og.png https://8.8.8.8/og.png https://[2001:4860:4860::8888]/og.png https://example.com./og.png https://xn--r8jz45g.jp/og.png].each do |url|
      expect(described_class.from(html(%(<meta property="og:image" content="#{url}">)), base)).to eq(url), url
    end
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
