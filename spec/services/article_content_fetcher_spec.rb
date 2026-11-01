# 外部通信は WebMock。ページは spec/fixtures/files/pages/*.html（手書き）
RSpec.describe ArticleContentFetcher do
  let(:article) { create(:article, url: "https://fixtures.example.com/posts/solid-queue", content: "フィードの抜粋") }
  let(:page) { file_fixture("pages/article.html").read }

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
      expect(article.content).to include("config.active_job.queue_adapter = :solid_queue")
      expect(article.content).not_to include("このブログについて")
      expect(article.content).not_to include("無断転載")
      expect(article.content).not_to include("フィードの抜粋")
    end
  end

  it "Shift_JIS のページも UTF-8 に直して保存する（Ruby 4 では readability の推定が動かない）" do
    stub_page(body: file_fixture("pages/sjis.html").binread, content_type: "text/html")

    described_class.new(article).call

    expect(article.reload.content_error).to be_nil
    expect(article.content.encoding).to eq(Encoding::UTF_8)
    expect(article.content).to include("自前で推定してから渡す必要がある")
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
    end

    it "本文の文字が readability の最小段落長に満たなければ「本文を抽出できません」（JS 描画のページなど）" do
      stub_page(body: "<html><body><div id='app'><nav><a href='/'>ホーム</a></nav>読み込み中…</div></body></html>")

      described_class.new(article).call
      expect(article.reload).to have_attributes(content: "フィードの抜粋", content_error: "本文を抽出できません")
    end

    it "HTTP エラー・接続エラーは HttpGet の文言で残す" do
      stub_page(status: 404, body: "")
      described_class.new(article).call
      expect(article.reload.content_error).to eq("サーバーエラー (HTTP 404)")

      stub_request(:get, article.url).to_timeout
      described_class.new(article).call
      expect(article.reload.content_error).to eq("接続エラー (Net::OpenTimeout)")
    end

    it "想定外の例外はそのまま上げる" do
      stub_page
      allow(Readability::Document).to receive(:new).and_raise(NoMethodError, "bug")

      expect { described_class.new(article).call }.to raise_error(NoMethodError)
    end
  end
end
