RSpec.describe FetchArticleContentJob, type: :job do
  let(:article) { create(:article) }

  it "feeds キューに積まれる" do
    expect(described_class.new(article).queue_name).to eq("feeds")
  end

  it "ArticleContentFetcher に記事を渡す" do
    fetcher = instance_double(ArticleContentFetcher, call: nil)
    allow(ArticleContentFetcher).to receive(:new).with(article).and_return(fetcher)

    described_class.perform_now(article)

    expect(fetcher).to have_received(:call)
  end

  it "取得済み（content_fetched_at あり）なら何もしない（冪等）" do
    article.update!(content_fetched_at: Time.current)
    allow(ArticleContentFetcher).to receive(:new)

    described_class.perform_now(article)

    expect(ArticleContentFetcher).not_to have_received(:new)
  end

  it "TransientError は待ってやり直し、尽きたら失敗として記録する" do
    fetcher = instance_double(ArticleContentFetcher)
    allow(ArticleContentFetcher).to receive(:new).with(article).and_return(fetcher)
    allow(fetcher).to receive(:call).and_raise(HttpGet::TransientError, "サーバーエラー (HTTP 503)")
    allow(fetcher).to receive(:record_failure)

    described_class.perform_now(article)
    expect(described_class).to have_been_enqueued.with(article)
    expect(fetcher).not_to have_received(:record_failure)

    perform_enqueued_jobs { described_class.perform_later(article) }
    expect(fetcher).to have_received(:call).at_least(3).times
    expect(fetcher).to have_received(:record_failure).with("サーバーエラー (HTTP 503)").once
  end

  it "同じホストの Job は 1 本ずつ（concurrency key は記事 URL のホスト）" do
    job = described_class.new(article)
    expect(job).to be_concurrency_limited
    expect(job.concurrency_key).to end_with("/fixtures.example.com")
    expect(described_class.host_of(build(:article, url: "not a url"))).to eq("not a url")
  end

  it "記事が見つからなければ待ってやり直し（本番は記事のコミットより先にワーカーが取ることがある）、尽きたら捨てる" do
    article.destroy!

    # ブロック形なら、やり直しで積まれた Job も待ち時間なしで続けて走る
    log = StringIO.new
    with_rails_logger(ActiveSupport::Logger.new(log)) do
      expect { perform_enqueued_jobs { described_class.perform_later(article) } }.not_to raise_error
    end
    expect(log.string).to include("[feeds] FetchArticleContentJob discarded:")
    expect(enqueued_jobs).to be_empty
  end

  describe "取得を試し終えたら、読むと決めた記事の要約を積む" do
    let(:article) { create(:article, :unsummarized, :opened) }
    let(:fetcher) { instance_double(ArticleContentFetcher) }

    before do
      allow(ArticleContentFetcher).to receive(:new).with(article).and_return(fetcher)
      allow(fetcher).to receive(:call) { article.update!(content_fetched_at: Time.current) }
    end

    it "「読む」で行ができていれば積む（本文取得を待っていた要約）" do
      described_class.perform_now(article)

      expect(Claude::SummarizeArticleJob).to have_been_enqueued.with(article)
    end

    it "本文の取得に失敗しても積む（フィードの本文で要約する）" do
      allow(fetcher).to receive(:call) { article.update!(content_fetched_at: Time.current, content_error: "本文を抽出できません") }

      described_class.perform_now(article)

      expect(Claude::SummarizeArticleJob).to have_been_enqueued.with(article)
    end

    it "まだ読むと決めていない記事は積まない（読まない記事に払わない）" do
      article.reading.destroy!

      described_class.perform_now(article.reload)

      expect(Claude::SummarizeArticleJob).not_to have_been_enqueued
    end

    it "やり直しが尽きて失敗を記録した後も積む" do
      allow(fetcher).to receive(:call).and_raise(HttpGet::TransientError, "サーバーエラー (HTTP 503)")
      allow(fetcher).to receive(:record_failure) { article.update!(content_fetched_at: Time.current, content_error: "サーバーエラー (HTTP 503)") }

      perform_enqueued_jobs(only: described_class) { described_class.perform_later(article) }

      expect(fetcher).to have_received(:record_failure).once
      expect(Claude::SummarizeArticleJob).to have_been_enqueued.with(article).once
    end
  end
end
