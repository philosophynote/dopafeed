RSpec.describe Claude::SummarizeArticleJob, type: :job do
  let(:article) { create(:article, :awaiting_summary) }
  let(:summarizer) { instance_double(Claude::Summarizer) }
  let(:three_lines) { "・1 行目\n・2 行目\n・3 行目" }

  before { allow(Claude::Summarizer).to receive(:new).with(article).and_return(summarizer) }

  it "claude キューに積まれる" do
    expect(described_class.new(article).queue_name).to eq("claude")
  end

  it "要約を書き、前回の失敗の記録を消す" do
    article.update!(summary_failed_at: Time.current, summary_error: "本文が空")
    allow(summarizer).to receive(:call).and_return(three_lines)

    described_class.perform_now(article)

    expect(article.reload).to have_attributes(summary: three_lines, summary_failed_at: nil, summary_error: nil)
  end

  it "要約済みなら呼ばない（冪等。二度払いしない）" do
    article.update!(summary: three_lines)

    described_class.perform_now(article)

    expect(Claude::Summarizer).not_to have_received(:new)
  end

  it "積まれた後に別の経路で要約が付いていても呼ばない（呼ぶ直前に読み直す）" do
    Article.find(article.id).update!(summary: three_lines)

    described_class.perform_now(article)

    expect(Claude::Summarizer).not_to have_received(:new)
  end

  it "同じ記事の Job が同時に走っても、先に付いた要約を上書きしない" do
    other = "・別\n・の\n・要約"
    allow(summarizer).to receive(:call) do
      Article.find(article.id).update!(summary: other)
      three_lines
    end

    described_class.perform_now(article)

    expect(article.reload.summary).to eq(other)
  end

  it "本文なし・形式不正・4xx は失敗として記録し、やり直さない" do
    allow(summarizer).to receive(:call).and_raise(Claude::Summarizer::EmptyContent, "本文が空")

    freeze_time do
      described_class.perform_now(article)
      expect(article.reload).to have_attributes(summary: nil, summary_failed_at: Time.current, summary_error: "本文が空")
    end
    expect(described_class).not_to have_been_enqueued
  end

  it "TransientError は待ってやり直し、尽きたら失敗として記録する" do
    allow(summarizer).to receive(:call).and_raise(Claude::Summarizer::TransientError, "API エラー (HTTP 529)")

    described_class.perform_now(article)
    expect(described_class).to have_been_enqueued.with(article)
    expect(article.reload.summary_failed_at).to be_nil

    # 積んだ Job を待ち時間なしで続けて走らせると、既定の回数で尽きて記録する
    perform_enqueued_jobs { described_class.perform_later(article) }
    expect(summarizer).to have_received(:call).at_least(3).times
    expect(article.reload).to have_attributes(summary: nil, summary_error: "API エラー (HTTP 529)")
    expect(article.summary_failed_at).to be_present
  end

  it "予算切れは捨て、記事には何も残さない（翌日の定期ジョブが拾う）" do
    allow(summarizer).to receive(:call).and_raise(Claude::Budget::Exhausted, "Claude daily call limit reached (200/200)")

    expect { described_class.perform_now(article) }.not_to raise_error
    expect(enqueued_jobs).to be_empty
    expect(article.reload).to have_attributes(summary: nil, summary_failed_at: nil, summary_error: nil)
  end

  it "同じ記事の Job が重なったら 2 本目を捨てる（concurrency key は記事 id）" do
    job = described_class.new(article)
    expect(job).to be_concurrency_limited
    expect(job.concurrency_key).to end_with("/#{article.id}")
    expect(described_class.concurrency_on_conflict).to eq(:discard)
  end

  it "記事が消えていたら捨てる" do
    article.destroy!

    log = StringIO.new
    with_rails_logger(ActiveSupport::Logger.new(log)) do
      expect { perform_enqueued_jobs { described_class.perform_later(article) } }.not_to raise_error
    end
    expect(log.string).to include("[claude] Claude::SummarizeArticleJob discarded:")
    expect(enqueued_jobs).to be_empty
  end
end
