RSpec.describe FetchFeedJob, type: :job do
  let(:feed) { create(:feed) }

  it "feeds キューに積まれる" do
    expect(described_class.new(feed).queue_name).to eq("feeds")
  end

  it "積んだ後にフィードが消えていたら捨てる" do
    described_class.perform_later(feed)
    feed.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error
  end

  it "同じフィードの Job が待ち・実行中なら、後から積んだ方は捨てる（取得を 2 回走らせない）" do
    other = create(:feed)

    expect(described_class.concurrency_on_conflict).to eq(:discard)
    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.new(Feed.find(feed.id)).concurrency_key).to eq(described_class.new(feed).concurrency_key)
    expect(described_class.new(other).concurrency_key).not_to eq(described_class.new(feed).concurrency_key)
  end

  it "FeedFetcher にフィードを渡す" do
    fetcher = instance_double(FeedFetcher, call: nil)
    allow(FeedFetcher).to receive(:new).with(feed).and_return(fetcher)

    described_class.perform_now(feed)

    expect(fetcher).to have_received(:call)
  end
end
