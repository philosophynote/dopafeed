# 外部通信は WebMock。ページは spec/fixtures/files/pages/*.html（手書き）
RSpec.describe ArticleContentFetcher do
  let(:article) { create(:article, url: "https://fixtures.example.com/posts/solid-queue", content: "フィードの抜粋") }
  let(:page) { file_fixture("pages/article.html").read }
  # 文字コードの検証用。meta で charset を宣言するかはテストごとに変える
  let(:japanese_page) do
    <<~HTML
      <html><head>%{meta}<title>文字コードの罠</title></head>
      <body><article>
      <p>このページは UTF-8 以外で書かれている。本番の Ruby 4 では ruby-readability の文字コード推定が動かないので、自前で推定してから渡す必要がある。</p>
      <p>ここが UTF-8 に直って保存されていれば、要約ジョブに渡したときに文字化けしない。確認のための二つ目の段落で、二十五文字より長くしてある。</p>
      <p>三つ目の段落。readability は段落の長さで本文候補を点数づけするので、短すぎると本文として拾われない。</p>
      </article></body></html>
    HTML
  end

  def stub_page(body: page, status: 200, content_type: "text/html; charset=utf-8")
    stub_request(:get, article.url).to_return(status: status, body: body, headers: { "Content-Type" => content_type })
  end

  describe "本文が抜けたとき" do
    before { stub_page }

    it "content を readability の本文で上書きし、ナビやフッターは入れない" do
      result = nil
      freeze_time do
        result = described_class.new(article).call
        expect(article.reload).to have_attributes(content_fetched_at: Time.current, content_error: nil)
      end

      expect(result.status).to eq(:fetched)
      expect(article.content).to include("ワーカー 1 プロセス・3 スレッド")
      expect(article.content).to include("<h1>").and include("<pre><code>config.active_job.queue_adapter = :solid_queue</code></pre>")
      expect(article.content).not_to include("このブログについて")
      expect(article.content).not_to include("無断転載")
      expect(article.content).not_to include("フィードの抜粋")
    end
  end

  it "抜いた本文がフィードの本文より短ければ置き換えない（Zenn の長い抜粋を守る）" do
    article.update!(content: "<p>#{"フィードの長い抜粋。" * 100}</p>")
    stub_page

    result = described_class.new(article).call

    expect(result.status).to eq(:kept)
    expect(article.reload).to have_attributes(content_error: nil)
    expect(article.content).to include("フィードの長い抜粋。")
    expect(article.content_fetched_at).to be_present
  end

  describe "文字コード（Ruby 4 では readability の推定が動かないので自前で直す）" do
    it "meta の charset（Shift_JIS）を見て UTF-8 に直す" do
      body = (japanese_page % { meta: '<meta http-equiv="Content-Type" content="text/html; charset=Shift_JIS">' }).encode("Shift_JIS")
      stub_page(body: body, content_type: "text/html")

      described_class.new(article).call

      expect(article.reload.content_error).to be_nil
      expect(article.content.encoding).to eq(Encoding::UTF_8)
      expect(article.content).to include("自前で推定してから渡す必要がある")
    end

    it "ヘッダの charset（EUC-JP、meta なし）でも直す" do
      stub_page(body: (japanese_page % { meta: "" }).encode("EUC-JP"), content_type: "text/html; charset=EUC-JP")

      described_class.new(article).call

      expect(article.reload.content_error).to be_nil
      expect(article.content).to include("要約ジョブに渡したときに文字化けしない")
    end

    it "charset がどこにも無く UTF-8 でも読めなければ「文字コードを判定できません」（化けた本文で上書きしない）" do
      stub_page(body: (japanese_page % { meta: "" }).encode("EUC-JP"), content_type: "text/html")

      described_class.new(article).call

      expect(article.reload).to have_attributes(content: "フィードの抜粋", content_error: "文字コードを判定できません")
    end
  end

  describe "OGP 画像（og:image）" do
    let(:image_page) { page.sub("<head>", '<head><meta property="og:image" content="/images/og.png">') }

    it "本文が抜けたら、og:image をページの URL で絶対にして image_url に残す" do
      stub_page(body: image_page)

      described_class.new(article).call
      expect(article.reload.image_url).to eq("https://fixtures.example.com/images/og.png")
    end

    it "リダイレクトされたら、移った先の URL で相対の og:image を解く" do
      stub_request(:get, article.url).to_return(status: 301, headers: { "Location" => "https://moved.example.com/posts/1" })
      stub_request(:get, "https://moved.example.com/posts/1").to_return(status: 200, body: image_page, headers: { "Content-Type" => "text/html" })

      described_class.new(article).call
      expect(article.reload.image_url).to eq("https://moved.example.com/images/og.png")
    end

    it "フィードの本文の方が長くて置き換えなくても残す" do
      article.update!(content: "<p>#{"フィードの長い抜粋。" * 100}</p>")
      stub_page(body: image_page)

      expect(described_class.new(article).call.status).to eq(:kept)
      expect(article.reload.image_url).to eq("https://fixtures.example.com/images/og.png")
    end

    it "本文を抽出できない（JS 描画の）ページでも残す" do
      stub_page(body: '<html><head><meta property="og:image" content="https://cdn.example.com/og.png"></head><body><div id="app">読み込み中…</div></body></html>')

      described_class.new(article).call
      expect(article.reload).to have_attributes(content_error: "本文を抽出できません", image_url: "https://cdn.example.com/og.png")
    end

    it "HTML まで届かなかった・読めなかった失敗では、前に拾った画像を消さない" do
      article.update!(image_url: "https://cdn.example.com/old.png")
      [
        -> { stub_page(status: 404, body: "") },
        -> { stub_page(body: "%PDF-1.7", content_type: "application/pdf") },
        -> { stub_page(body: (japanese_page % { meta: "" }).encode("EUC-JP"), content_type: "text/html") }
      ].each do |stub|
        stub.call
        described_class.new(article).call
        expect(article.reload).to have_attributes(content_error: be_present, image_url: "https://cdn.example.com/old.png")
      end

      described_class.new(article).record_failure("サーバーエラー (HTTP 503)")
      expect(article.reload.image_url).to eq("https://cdn.example.com/old.png")
    end

    it "取り直したページに og:image が無くなっていたら空にする" do
      article.update!(image_url: "https://cdn.example.com/old.png")
      stub_page

      described_class.new(article).call
      expect(article.reload.image_url).to be_nil
    end
  end

  describe "失敗" do
    it "HTML でなければ取らず、Content-Type を残す" do
      stub_page(body: "%PDF-1.7", content_type: "application/pdf")

      result = nil
      freeze_time do
        result = described_class.new(article).call
        expect(article.reload).to have_attributes(content: "フィードの抜粋", content_fetched_at: Time.current, content_error: "HTML ではありません (application/pdf)")
      end
      expect(result).to have_attributes(status: :failed, error: "HTML ではありません (application/pdf)")

      stub_request(:get, article.url).to_return(status: 200, body: "no type")
      described_class.new(article).call
      expect(article.reload.content_error).to eq("HTML ではありません (不明)")
    end

    it "本文の文字が readability の最小段落長に満たなければ「本文を抽出できません」（JS 描画のページなど）" do
      stub_page(body: "<html><body><div id='app'><nav><a href='/'>ホーム</a></nav>読み込み中…</div></body></html>")

      described_class.new(article).call
      expect(article.reload).to have_attributes(content: "フィードの抜粋", content_error: "本文を抽出できません")
    end

    it "4xx は HttpGet の文言で残す" do
      stub_page(status: 404, body: "")
      described_class.new(article).call
      expect(article.reload.content_error).to eq("サーバーエラー (HTTP 404)")
    end

    it "内部ネットワークへ向く記事ページは取りに行かず、HttpGet の文言で残す" do
      stub_request(:get, article.url).to_return(status: 302, headers: { "Location" => "http://169.254.169.254/latest/meta-data/" })

      described_class.new(article).call
      expect(article.reload).to have_attributes(content: "フィードの抜粋", content_error: "内部ネットワークの URL です")
      expect(a_request(:get, "http://169.254.169.254/latest/meta-data/")).not_to have_been_made
    end

    it "5xx・接続エラーは記録せず TransientError を上げる（Job が待ってやり直す）" do
      stub_page(status: 503, body: "")
      expect { described_class.new(article).call }.to raise_error(HttpGet::TransientError, "サーバーエラー (HTTP 503)")

      stub_request(:get, article.url).to_timeout
      expect { described_class.new(article).call }.to raise_error(HttpGet::TransientError, "接続エラー (Net::OpenTimeout)")
      expect(article.reload).to have_attributes(content_fetched_at: nil, content_error: nil)
    end

    it "record_failure は content を残したまま失敗を記録する" do
      freeze_time do
        result = described_class.new(article).record_failure("サーバーエラー (HTTP 503)")
        expect(result).to have_attributes(status: :failed, error: "サーバーエラー (HTTP 503)")
        expect(article.reload).to have_attributes(content: "フィードの抜粋", content_fetched_at: Time.current, content_error: "サーバーエラー (HTTP 503)")
      end
    end

    it "想定外の例外はそのまま上げる" do
      stub_page
      allow(Readability::Document).to receive(:new).and_raise(NoMethodError, "bug")

      expect { described_class.new(article).call }.to raise_error(NoMethodError)
    end
  end
end
