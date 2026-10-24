require "test_helper"

module Claude
  class BaseJobTest < ActiveJob::TestCase
    class ExhaustingJob < Claude::BaseJob
      def perform
        raise Claude::Budget::Exhausted, "daily limit reached"
      end
    end

    class CountingJob < Claude::BaseJob
      def perform
        Claude::Budget.new(limit: 1).record!(purpose: "test", model: "test-model")
      end
    end

    test "claude キューに積まれる" do
      assert_equal "claude", ExhaustingJob.new.queue_name
    end

    test "予算切れは discard され、warn ログに Job 名と理由が出る（runbook 2-d の根拠）" do
      log = StringIO.new
      with_rails_logger(ActiveSupport::Logger.new(log)) do
        assert_nothing_raised { ExhaustingJob.perform_now }
      end

      assert_no_enqueued_jobs
      assert_includes log.string, "[claude] Claude::BaseJobTest::ExhaustingJob discarded: daily limit reached"
    end

    test "予算があれば普通に走る" do
      assert_difference("ClaudeApiCall.count", 1) { CountingJob.perform_now }
    end

    private

    def with_rails_logger(logger)
      original = Rails.logger
      Rails.logger = logger
      yield
    ensure
      Rails.logger = original
    end
  end
end
