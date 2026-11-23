# 失敗も 1 週 1 行に残す。行の無い週だけを呼ぶので、失敗した週を毎時呼び直して払い続けない。
# 呼ぶ前に job_id だけの行で週を押さえる。押さえずに呼ぶと、滞留した毎時の実行が同じ週をそれぞれ呼び、再試行の鎖も重なる。
class WeeklyComment < ApplicationRecord
  validates :week_start, presence: true
  validate :week_start_on_monday

  scope :succeeded, -> { where(failed_at: nil).where.not(body: nil) }

  def self.for_week(week_start)
    succeeded.find_by(week_start: week_start)
  end

  def self.record_failure!(week_start, message)
    row = find_by(week_start: week_start)
    return create!(week_start: week_start, failed_at: Time.current, error: message) if row.nil?

    row.update!(failed_at: Time.current, error: message) if row.pending?
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def pending?
    body.nil? && failed_at.nil?
  end

  def week_end
    week_start + (WeeklyReport::DAYS - 1)
  end

  private

  def week_start_on_monday
    errors.add(:week_start, :invalid) if week_start && week_start != week_start.beginning_of_week(WeeklyReport::WEEK_START)
  end
end
