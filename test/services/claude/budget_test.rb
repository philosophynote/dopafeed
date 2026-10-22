require "test_helper"

module Claude
  class BudgetTest < ActiveSupport::TestCase
    test "既定の上限は config/dopamine.yml の claude.daily_call_limit" do
      expected = Rails.application.config_for(:dopamine).dig(:claude, :daily_call_limit)
      assert_equal expected, Budget.new.limit
    end

    test "上限未満なら record! が台帳に 1 行足し、残りが減る" do
      budget = Budget.new(limit: 2)

      assert_difference("ClaudeApiCall.count", 1) { budget.record!(purpose: "summary", model: "test-model") }
      assert_equal 1, budget.used_today
      assert_equal 1, budget.remaining
      assert_not budget.exhausted?

      call = ClaudeApiCall.last
      assert_equal "summary", call.purpose
      assert_equal "test-model", call.model
    end

    test "上限ちょうどで Exhausted を投げ、行は作らない" do
      budget = Budget.new(limit: 2)
      2.times { budget.record!(purpose: "summary", model: "test-model") }

      assert budget.exhausted?
      assert_equal 0, budget.remaining
      assert_no_difference("ClaudeApiCall.count") do
        assert_raises(Budget::Exhausted) { budget.record!(purpose: "summary", model: "test-model") }
      end
    end

    test "日付が変わると数え直す（Time.zone の暦日）" do
      budget = Budget.new(limit: 1)

      travel_to Time.zone.local(2026, 10, 23, 23, 59) do
        budget.record!(purpose: "summary", model: "test-model")
        assert budget.exhausted?
      end

      travel_to Time.zone.local(2026, 10, 24, 0, 0) do
        assert_equal 0, budget.used_today
        assert_not budget.exhausted?
        assert_nothing_raised { budget.record!(purpose: "summary", model: "test-model") }
      end
    end

    test "remaining は負にならない（上限が後から下がっても）" do
      Budget.new(limit: 3).tap { |b| 3.times { b.record!(purpose: "summary", model: "test-model") } }
      assert_equal 0, Budget.new(limit: 2).remaining
    end
  end
end
