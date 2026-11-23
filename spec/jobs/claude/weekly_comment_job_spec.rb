RSpec.describe Claude::WeeklyCommentJob, type: :job do
  let(:reset_hour) { Dopamine.settings.dig(:daily_goal, :reset_hour) }
  # 2026-11-18（水）の正午。先週は 11/9（月）〜 11/15（日）
  let(:now) { Time.zone.local(2026, 11, 18, reset_hour) + 8.hours }
  let(:last_week) { Date.new(2026, 11, 9) }
  let(:commenter) { instance_double(Claude::WeeklyCommenter, call: "先週は 1 本。来週はもう 1 本。", model: "curation-model") }
  let(:monday_reset) { Time.zone.local(2026, 11, 16, reset_hour) }

  def complete(at)
    create(:reading, article: create(:article), opened_at: at - 5.minutes, returned_at: at, completed_at: at)
  end

  before { allow(Claude::WeeklyCommenter).to receive(:new).and_return(commenter) }

  it "claude キューに積まれる" do
    expect(described_class.new.queue_name).to eq("claude")
  end

  it "先週に完読があれば、先週の WeeklyReport でひとことを生成して 1 行書く" do
    complete(Time.zone.local(2026, 11, 12, 12))

    travel_to(now) { described_class.perform_now }

    expect(Claude::WeeklyCommenter).to have_received(:new).with(having_attributes(start_day: last_week, count: 1))
    expect(WeeklyComment.sole).to have_attributes(week_start: last_week, body: "先週は 1 本。来週はもう 1 本。", model: "curation-model", failed_at: nil)
  end

  it "月曜の reset_hour の手前ではまだ前の週を書かず、過ぎた回で書く。その手前の完読は前の週に数える" do
    complete(monday_reset - 1.minute)

    travel_to(monday_reset - 1.minute) { described_class.perform_now }
    expect(WeeklyComment.where(week_start: last_week)).to be_none

    travel_to(monday_reset + 27.minutes) { described_class.perform_now }
    expect(Claude::WeeklyCommenter).to have_received(:new).with(having_attributes(start_day: last_week, count: 1))
    expect(WeeklyComment.where(week_start: last_week).sole.body).to be_present
  end

  it "週を渡せばその週を書く" do
    complete(Time.zone.local(2026, 11, 4, 12))

    travel_to(now) { described_class.perform_now(Date.new(2026, 11, 2)) }

    expect(WeeklyComment.sole.week_start).to eq(Date.new(2026, 11, 2))
  end

  it "呼んでいる間に別の実行が同じ週の行を書いていたら、その行を残して静かに終える" do
    complete(Time.zone.local(2026, 11, 12, 12))
    allow(commenter).to receive(:call) do
      WeeklyComment.create!(week_start: last_week, body: "先に書いたひとこと")
      "後のひとこと"
    end

    travel_to(now) { expect { described_class.perform_now }.not_to raise_error }

    expect(WeeklyComment.sole.body).to eq("先に書いたひとこと")
  end

  it "再試行は最初に決めた週で積み直す（再試行が月曜をまたいでも別の週を呼ばない）" do
    complete(Time.zone.local(2026, 11, 12, 12))
    allow(commenter).to receive(:call).and_raise(Claude::WeeklyCommenter::TransientError, "接続エラー")

    travel_to(now) { described_class.perform_now }

    expect(described_class).to have_been_enqueued.with(last_week)
  end

  it "その週の行が既にあれば呼ばない（同じ週に再生成しない）" do
    complete(Time.zone.local(2026, 11, 12, 12))
    WeeklyComment.create!(week_start: last_week, body: "前のひとこと")

    travel_to(now) { described_class.perform_now }

    expect(Claude::WeeklyCommenter).not_to have_received(:new)
    expect(WeeklyComment.sole.body).to eq("前のひとこと")
  end

  it "失敗の行がある週も呼び直さない" do
    complete(Time.zone.local(2026, 11, 12, 12))
    WeeklyComment.create!(week_start: last_week, failed_at: now - 1.hour, error: "応答の形式が不正")

    travel_to(now) { described_class.perform_now }

    expect(Claude::WeeklyCommenter).not_to have_received(:new)
  end

  it "先週の完読が 0 本なら呼ばず、行も書かない（今週の完読は数えない）" do
    complete(now - 1.hour)

    travel_to(now) { described_class.perform_now }

    expect(Claude::WeeklyCommenter).not_to have_received(:new)
    expect(WeeklyComment.count).to eq(0)
  end

  it "形式不正などの失敗は失敗の行を書き、例外を外に出さない" do
    complete(Time.zone.local(2026, 11, 12, 12))
    allow(commenter).to receive(:call).and_raise(Claude::WeeklyCommenter::MalformedResponse, "応答の形式が不正")

    travel_to(now) { described_class.perform_now }

    expect(WeeklyComment.sole).to have_attributes(week_start: last_week, body: nil, error: "応答の形式が不正")
    expect(WeeklyComment.sole.failed_at).to be_present
  end

  it "一時的な失敗は再試行に回し、尽きたら失敗の行を書く" do
    complete(Time.zone.local(2026, 11, 12, 12))
    allow(commenter).to receive(:call).and_raise(Claude::WeeklyCommenter::TransientError, "接続エラー")

    travel_to(now) do
      expect { described_class.perform_now }.to have_enqueued_job(described_class)
      expect(WeeklyComment.count).to eq(0)

      perform_enqueued_jobs { described_class.perform_now }
    end

    expect(WeeklyComment.sole).to have_attributes(week_start: last_week, error: "接続エラー")
  end

  it "日次上限なら行を書かずに捨てる（翌日以降の回で追いつく）" do
    complete(Time.zone.local(2026, 11, 12, 12))
    allow(commenter).to receive(:call).and_raise(Claude::Budget::Exhausted, "limit")

    travel_to(now) { expect { described_class.perform_now }.not_to raise_error }

    expect(WeeklyComment.count).to eq(0)
  end
end
