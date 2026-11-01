RSpec.describe Claude::BaseJob, type: :job do
  # 予算切れを投げる Job。discard_on の挙動を見る
  let(:exhausting_job) do
    stub_const("ExhaustingJob", Class.new(described_class) do
      def perform
        raise Claude::Budget::Exhausted, "daily limit reached"
      end
    end)
  end

  # 予算を 1 回使う Job。普通に走ることを見る
  let(:counting_job) do
    stub_const("CountingJob", Class.new(described_class) do
      def perform
        Claude::Budget.new(limit: 1).record!(purpose: "test", model: "test-model")
      end
    end)
  end

  it "claude キューに積まれる" do
    expect(exhausting_job.new.queue_name).to eq("claude")
  end

  it "予算切れは discard され、warn ログに Job 名と理由が出る（runbook 2-d の根拠）" do
    log = StringIO.new
    with_rails_logger(ActiveSupport::Logger.new(log)) do
      expect { exhausting_job.perform_now }.not_to raise_error
    end

    expect(enqueued_jobs).to be_empty
    expect(log.string).to include("[claude] ExhaustingJob discarded: daily limit reached")
  end

  it "予算があれば普通に走る" do
    expect { counting_job.perform_now }.to change(ClaudeApiCall, :count).by(1)
  end
end
