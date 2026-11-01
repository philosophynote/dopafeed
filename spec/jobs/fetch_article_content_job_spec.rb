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

    # 積んだ Job を待ち時間なしで続けて走らせると、既定の回数で尽きて記録する
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

  it "積んだ後に記事が消えていたら捨てる" do
    described_class.perform_later(article)
    article.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error
  end
end
