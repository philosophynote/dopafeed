# 外部通信は WebMock。本文は spec/fixtures/files/feeds/*.xml（手書き）
RSpec.describe FeedFetcher do
  let(:feed) { create(:feed, url: "https://fixtures.example.com/rss/feed.xml") }
  let(:rss) { file_fixture("feeds/rss2.xml").read }
  let(:atom) { file_fixture("feeds/atom.xml").read }

  def stub_feed(body: rss, status: 200, headers: {})
    stub_request(:get, feed.url).to_return(status: status, body: body, headers: { "Content-Type" => "application/rss+xml" }.merge(headers))
  end

  describe "200 で新しいフィードを取ったとき" do
    before { stub_feed(headers: { "ETag" => '"v1"', "Last-Modified" => "Thu, 01 Oct 2026 00:00:00 GMT" }) }

    it "title と http(s) の url がある item だけ記事にし、列を埋める" do
      result = nil
      expect { result = described_class.new(feed).call }.to change(feed.articles, :count).by(3)
      expect(result.status).to eq(:updated)
      expect(result.created).to eq(3)
      expect(feed.articles.pluck(:guid)).to contain_exactly("rss-1", "rss-2", "https://fixtures.example.com/rss/3")

      first = feed.articles.find_by!(guid: "rss-1")
      expect(first).to have_attributes(title: "RSS 記事 1", url: "https://fixtures.example.com/rss/1", summary: nil)
      expect(first.published_at).to eq(Time.zone.parse("2026-10-01 09:00:00 +09:00"))
      expect(first.content).to include("<strong>本文</strong>")
    end

    it "作った記事の分だけ FetchArticleContentJob を積む（既存の分は積まない）" do
      create(:article, url: "https://fixtures.example.com/rss/1")
      expect { described_class.new(feed).call }.to have_enqueued_job(FetchArticleContentJob).exactly(2).times
      expect(FetchArticleContentJob).to have_been_enqueued.with(feed.articles.find_by!(guid: "rss-2"))
    end

    it "Job を積めなければ記事も作らない（次の取得でやり直す。本番は queue が別 DB）" do
      allow(FetchArticleContentJob).to receive(:perform_later).and_raise(ActiveRecord::ConnectionNotEstablished, "queue db")

      expect { described_class.new(feed).call }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      expect(Article.count).to eq(0)
    end

    it "content:encoded が無ければ description を本文にする" do
      described_class.new(feed).call
      expect(feed.articles.find_by!(guid: "rss-2").content).to eq("2 件目の概要だけ（content:encoded なし）")
    end

    it "guid・日付・本文の無い item は url を guid にして nil のまま保存する" do
      described_class.new(feed).call
      expect(feed.articles.find_by!(url: "https://fixtures.example.com/rss/3")).to have_attributes(guid: "https://fixtures.example.com/rss/3", published_at: nil, content: nil)
    end

    it "feeds に試行時刻・ETag・Last-Modified を残し、last_error を消す" do
      feed.update!(last_error: "サーバーエラー (HTTP 503)")
      freeze_time do
        described_class.new(feed).call
        expect(feed.reload).to have_attributes(last_fetched_at: Time.current, last_error: nil, etag: '"v1"', last_modified: "Thu, 01 Oct 2026 00:00:00 GMT")
      end
    end
  end

  describe "二度目の取得" do
    before { stub_feed }

    it "同じ本文なら記事は増えない（guid で一致）" do
      described_class.new(feed).call
      expect { described_class.new(feed).call }.not_to change(Article, :count)
    end

    it "guid が変わっても url が同じなら増えない" do
      described_class.new(feed).call
      feed.articles.each_with_index { |article, i| article.update_column(:guid, "old-guid-#{i}") }
      expect { described_class.new(feed).call }.not_to change(Article, :count)
    end

    it "同じ url が別のフィードにあれば作らない（url は全体で一意）" do
      create(:article, url: "https://fixtures.example.com/rss/1")
      described_class.new(feed).call
      expect(feed.articles.pluck(:guid)).to contain_exactly("rss-2", "https://fixtures.example.com/rss/3")
    end

    it "重なった Job に先を越されても（url と [feed_id, guid] の一意制約）落ちずに飛ばす" do
      create(:article, feed: feed, guid: "rss-1", url: "https://fixtures.example.com/rss/1-moved")
      create(:article, url: "https://fixtures.example.com/rss/2")
      allow(Article).to receive(:exists?).and_return(false)
      allow(feed.articles).to receive(:exists?).and_return(false)

      result = nil
      expect { result = described_class.new(feed).call }.not_to raise_error
      expect(result).to have_attributes(status: :updated, created: 1)
      expect(feed.reload.last_error).to be_nil
      expect(feed.articles.where(guid: "rss-1").count).to eq(1)
      expect(Article.where(url: "https://fixtures.example.com/rss/2").count).to eq(1)
    end

    it "既存の記事は更新しない（要約と読了を守る）" do
      described_class.new(feed).call
      article = feed.articles.find_by!(guid: "rss-1")
      article.update!(title: "手で直した題", summary: "・要約")
      described_class.new(feed).call
      expect(article.reload).to have_attributes(title: "手で直した題", summary: "・要約")
    end

    it "etag と last_modified があれば条件付きヘッダを送る" do
      feed.update!(etag: '"v1"', last_modified: "Thu, 01 Oct 2026 00:00:00 GMT")
      described_class.new(feed).call
      expect(a_request(:get, feed.url).with(headers: { "If-None-Match" => '"v1"', "If-Modified-Since" => "Thu, 01 Oct 2026 00:00:00 GMT" })).to have_been_made
    end
  end

  describe "304 Not Modified" do
    before do
      feed.update!(etag: '"v1"', last_error: "サーバーエラー (HTTP 503)")
      stub_feed(status: 304, body: "")
    end

    it "解析せず、試行時刻だけ更新して etag を残す" do
      result = nil
      freeze_time do
        expect { result = described_class.new(feed).call }.not_to change(Article, :count)
        expect(result.status).to eq(:not_modified)
        expect(feed.reload).to have_attributes(last_fetched_at: Time.current, last_error: nil, etag: '"v1"')
      end
    end
  end

  describe "Atom" do
    before { stub_feed(body: atom) }

    it "id を guid に、content か summary を本文にする" do
      described_class.new(feed).call
      expect(feed.articles.pluck(:guid)).to contain_exactly(*(1..4).map { |n| "tag:fixtures.example.com,2026:atom/#{n}" })
      expect(feed.articles.find_by!(guid: "tag:fixtures.example.com,2026:atom/1").content).to eq("<p>Atom の本文</p>")
      expect(feed.articles.find_by!(guid: "tag:fixtures.example.com,2026:atom/2").content).to eq("Atom の概要だけ")
    end

    it "xhtml の content と summary はタグを残す" do
      described_class.new(feed).call
      expect(feed.articles.find_by!(guid: "tag:fixtures.example.com,2026:atom/3").content).to eq(%(<p>xhtml の<strong>本文</strong></p>\n<pre><code>puts "hi"</code></pre>))
      expect(feed.articles.find_by!(guid: "tag:fixtures.example.com,2026:atom/4").content).to eq("概要の<em>強調</em>")
    end
  end

  describe "リダイレクト" do
    it "Location を追って取る" do
      stub_feed(status: 301, body: "", headers: { "Location" => "https://fixtures.example.com/moved.xml" })
      stub_request(:get, "https://fixtures.example.com/moved.xml").to_return(status: 200, body: rss)

      expect { described_class.new(feed).call }.to change(Article, :count).by(3)
      expect(feed.reload.last_error).to be_nil
    end

    it "相対パスの Location も追う" do
      stub_feed(status: 302, body: "", headers: { "Location" => "/moved.xml" })
      stub_request(:get, "https://fixtures.example.com/moved.xml").to_return(status: 200, body: rss)

      expect { described_class.new(feed).call }.to change(Article, :count).by(3)
    end

    it "Location の無い 3xx は HTTP エラーとして残す" do
      stub_feed(status: 301, body: "")

      described_class.new(feed).call
      expect(feed.reload.last_error).to eq("サーバーエラー (HTTP 301)")
    end

    it "上限を超えたら失敗として記録する" do
      stub_feed(status: 301, body: "", headers: { "Location" => feed.url })

      result = described_class.new(feed).call
      expect(result.status).to eq(:failed)
      expect(feed.reload.last_error).to eq("リダイレクトが多すぎます")
    end
  end

  describe "失敗" do
    it "HTTP エラーは Feeds 画面の文言で残し、記事は作らない" do
      stub_feed(status: 503, body: "")

      result = nil
      freeze_time do
        expect { result = described_class.new(feed).call }.not_to change(Article, :count)
        expect(result).to have_attributes(status: :failed, error: "サーバーエラー (HTTP 503)")
        expect(feed.reload).to have_attributes(last_fetched_at: Time.current, last_error: "サーバーエラー (HTTP 503)")
      end
    end

    it "接続エラー（タイムアウト・DNS・切断）は例外名つきで残す" do
      stub_request(:get, feed.url).to_timeout
      described_class.new(feed).call
      expect(feed.reload.last_error).to eq("接続エラー (Net::OpenTimeout)")

      stub_request(:get, feed.url).to_raise(SocketError)
      described_class.new(feed).call
      expect(feed.reload.last_error).to eq("接続エラー (SocketError)")

      stub_request(:get, feed.url).to_raise(Errno::ECONNRESET)
      described_class.new(feed).call
      expect(feed.reload.last_error).to eq("接続エラー (Errno::ECONNRESET)")
    end

    it "http(s) でない URL は取りに行かず残す" do
      feed.update!(url: "mailto:nao@example.com")

      described_class.new(feed).call
      expect(feed.reload.last_error).to eq("URL が http(s) ではありません")
    end

    it "フィードでない XML・途中で切れた XML・空の本文は「フィードを解析できません」" do
      [ "<html><body>not a feed</body></html>", rss[0, rss.length / 2], "" ].each do |body|
        stub_feed(body: body)
        described_class.new(feed).call
        expect(feed.reload.last_error).to eq("フィードを解析できません"), "body: #{body[0, 30].inspect}"
      end
      expect(Article.count).to eq(0)
    end

    it "想定外の例外はそのまま上げる（Solid Queue の失敗に残す）" do
      stub_feed
      allow(Feedjira).to receive(:parse).and_raise(NoMethodError, "bug")

      expect { described_class.new(feed).call }.to raise_error(NoMethodError)
    end
  end
end
