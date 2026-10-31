RSpec.describe Claude::Budget do
  it "既定の上限は config/dopamine.yml の claude.daily_call_limit" do
    expected = Rails.application.config_for(:dopamine).dig(:claude, :daily_call_limit)
    expect(described_class.new.limit).to eq(expected)
  end

  it "上限未満なら record! が台帳に 1 行足し、残りが減る" do
    budget = described_class.new(limit: 2)

    expect { budget.record!(purpose: "summary", model: "test-model") }.to change(ClaudeApiCall, :count).by(1)
    expect(budget.used_today).to eq(1)
    expect(budget.remaining).to eq(1)
    expect(budget).not_to be_exhausted

    call = ClaudeApiCall.last
    expect(call.purpose).to eq("summary")
    expect(call.model).to eq("test-model")
  end

  it "上限ちょうどで Exhausted を投げ、行は作らない" do
    budget = described_class.new(limit: 2)
    2.times { budget.record!(purpose: "summary", model: "test-model") }

    expect(budget).to be_exhausted
    expect(budget.remaining).to eq(0)
    expect {
      expect { budget.record!(purpose: "summary", model: "test-model") }.to raise_error(Claude::Budget::Exhausted)
    }.not_to change(ClaudeApiCall, :count)
  end

  it "日付が変わると数え直す（Time.zone の暦日）" do
    budget = described_class.new(limit: 1)

    travel_to Time.zone.local(2026, 10, 23, 23, 59) do
      budget.record!(purpose: "summary", model: "test-model")
      expect(budget).to be_exhausted
    end

    travel_to Time.zone.local(2026, 10, 24, 0, 0) do
      expect(budget.used_today).to eq(0)
      expect(budget).not_to be_exhausted
      expect { budget.record!(purpose: "summary", model: "test-model") }.not_to raise_error
    end
  end

  it "remaining は負にならず、使用数が上限を超えていても exhausted?" do
    described_class.new(limit: 3).tap { |b| 3.times { b.record!(purpose: "summary", model: "test-model") } }

    budget = described_class.new(limit: 2)
    expect(budget.remaining).to eq(0)
    expect(budget).to be_exhausted
  end

  it "上限 0 なら最初の 1 回から Exhausted" do
    budget = described_class.new(limit: 0)
    expect(budget).to be_exhausted
    expect {
      expect { budget.record!(purpose: "summary", model: "test-model") }.to raise_error(Claude::Budget::Exhausted)
    }.not_to change(ClaudeApiCall, :count)
  end

  it "Exhausted のメッセージに使用数と上限が入る（runbook が読む）" do
    budget = described_class.new(limit: 1)
    budget.record!(purpose: "summary", model: "test-model")
    expect { budget.record!(purpose: "summary", model: "test-model") }
      .to raise_error(Claude::Budget::Exhausted, /\(1\/1\)/)
  end
end
