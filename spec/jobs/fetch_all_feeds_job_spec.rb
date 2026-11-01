RSpec.describe FetchAllFeedsJob, type: :job do
  it "フィードごとに FetchFeedJob を 1 つ積む" do
    feeds = create_list(:feed, 3)

    described_class.perform_now

    feeds.each { |feed| expect(FetchFeedJob).to have_been_enqueued.with(feed) }
    expect(enqueued_jobs.size).to eq(3)
  end

  it "フィードが無ければ何も積まない" do
    described_class.perform_now
    expect(enqueued_jobs).to be_empty
  end
end
