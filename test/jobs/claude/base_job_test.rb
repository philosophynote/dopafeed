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

    test "予算切れは discard され、再試行されない" do
      assert_nothing_raised { ExhaustingJob.perform_now }
      assert_no_enqueued_jobs
    end

    test "予算があれば普通に走る" do
      assert_difference("ClaudeApiCall.count", 1) { CountingJob.perform_now }
    end
  end
end
