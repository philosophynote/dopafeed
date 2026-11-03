RSpec.describe Claude::SummarizePendingArticlesJob, type: :job do
  def enqueued_articles
    enqueued_jobs.select { |job| job[:job] == Claude::SummarizeArticleJob }.map { |job| GlobalID::Locator.locate(job[:args].first["_aj_globalid"]) }
  end

  it "claude キューに積まれる" do
    expect(described_class.new.queue_name).to eq("claude")
  end

  it "要約待ちの記事だけを新しい順に積み、積んだ数を返す" do
    older = create(:article, :awaiting_summary, published_at: Time.zone.local(2026, 10, 1, 9))
    newer = create(:article, :awaiting_summary, published_at: Time.zone.local(2026, 10, 2, 9))
    create(:article)
    create(:article, :awaiting_summary, summary_failed_at: Time.current, summary_error: "本文が空")
    create(:article, :unsummarized)

    expect(described_class.perform_now).to eq(2)
    expect(enqueued_articles).to eq([ newer, older ])
  end

  it "その日の予算の残りで頭打ちにする（新しい方から）" do
    allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, remaining: 2))
    articles = Array.new(3) { |n| create(:article, :awaiting_summary, published_at: Time.zone.local(2026, 10, 1 + n, 9)) }

    expect(described_class.perform_now).to eq(2)
    expect(enqueued_articles).to eq([ articles[2], articles[1] ])
  end

  it "残りが 0 なら積まない" do
    allow(Claude::Budget).to receive(:new).and_return(instance_double(Claude::Budget, remaining: 0))
    create(:article, :awaiting_summary)

    expect(described_class.perform_now).to eq(0)
    expect(enqueued_jobs).to be_empty
  end
end
