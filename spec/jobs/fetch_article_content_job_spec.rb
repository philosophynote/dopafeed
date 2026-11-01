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

  it "積んだ後に記事が消えていたら捨てる" do
    described_class.perform_later(article)
    article.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error
  end
end
