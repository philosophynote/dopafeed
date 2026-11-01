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

  it "FeedFetcher にフィードを渡す" do
    fetcher = instance_double(FeedFetcher, call: nil)
    allow(FeedFetcher).to receive(:new).with(feed).and_return(fetcher)

    described_class.perform_now(feed)

    expect(fetcher).to have_received(:call)
  end
end
