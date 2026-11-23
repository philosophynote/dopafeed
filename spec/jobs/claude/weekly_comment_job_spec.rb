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

  it "呼ぶ前にその週を自分の job_id で押さえ、別の実行が押さえている週は呼ばない（滞留した毎時の Job が再試行の鎖を重ねない）" do
    complete(Time.zone.local(2026, 11, 12, 12))
    WeeklyComment.create!(week_start: last_week, job_id: "another-job")

    travel_to(now) { described_class.perform_now }

    expect(Claude::WeeklyCommenter).not_to have_received(:new)
    expect(WeeklyComment.sole).to have_attributes(job_id: "another-job", body: nil, failed_at: nil)
  end

  it "自分が押さえた週の再試行は呼び直し、書き終えたら同じ行に本文を入れる" do
    complete(Time.zone.local(2026, 11, 12, 12))
    job = described_class.new
    WeeklyComment.create!(week_start: last_week, job_id: job.job_id)

    travel_to(now) { job.perform_now }

    expect(WeeklyComment.sole).to have_attributes(job_id: job.job_id, body: "先週は 1 本。来週はもう 1 本。")
  end

  it "呼んでいる間に別の実行が同じ週の行を作っても、例外を出さずに終える" do
    complete(Time.zone.local(2026, 11, 12, 12))
    allow(WeeklyComment).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

    travel_to(now) { expect { described_class.perform_now }.not_to raise_error }

    expect(Claude::WeeklyCommenter).not_to have_received(:new)
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

  it "一時的な失敗は押さえた行を残して再試行に回し、尽きたら同じ行を失敗にする" do
    complete(Time.zone.local(2026, 11, 12, 12))
    allow(commenter).to receive(:call).and_raise(Claude::WeeklyCommenter::TransientError, "接続エラー")
    job = described_class.new

    travel_to(now) do
      expect { job.perform_now }.to have_enqueued_job(described_class)
      expect(WeeklyComment.sole).to have_attributes(job_id: job.job_id, body: nil, failed_at: nil)

      perform_enqueued_jobs { job.perform_now }
    end

    expect(WeeklyComment.sole).to have_attributes(week_start: last_week, job_id: job.job_id, error: "接続エラー")
  end

  it "日次上限なら押さえた行を外して捨てる（翌日以降の回で追いつく）" do
    complete(Time.zone.local(2026, 11, 12, 12))
    allow(commenter).to receive(:call).and_raise(Claude::Budget::Exhausted, "limit")

    travel_to(now) { expect { described_class.perform_now }.not_to raise_error }

    expect(WeeklyComment.count).to eq(0)
  end
end
