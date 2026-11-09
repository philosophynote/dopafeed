# 今日のゴール（宝箱）。1 日（{ReadingDay}）につき 1 行。
# achieved_at が入ったら宝箱は開いた（2 回目は開かない）。数え方は {DailySummary}
class DailyGoal < ApplicationRecord
  validates :day, presence: true, uniqueness: true

  def achieved?
    achieved_at.present?
  end

  # その時刻の読書日の完読が daily_goal.articles に達していれば、達成の行を 1 つ作る。
  # 行があれば何もしない（達成は 1 日 1 回）。同時に 2 本届いて後の 1 本が一意性（検証か DB の制約）で落ちたら先に入った行を使う。
  # 描くときに書かず、完読を判定した瞬間にだけ書く（開いた回数で増えない）
  #
  # @param at [Time] 完読を判定した時刻
  # @return [DailyGoal, nil] まだ届いていなければ nil
  def self.achieve_if_reached!(at: Time.current)
    day = ReadingDay.of(at)
    find_by(day: day) || (DailySummary.new(day).reached? ? create!(day: day, achieved_at: at) : nil)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_by!(day: day)
  end
end
