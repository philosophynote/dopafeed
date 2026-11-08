# 一覧の上の 1 行（ストリーク・今日の本数・カードの枚数・連続）に出す数字をビューへ渡す。
# 数字の出し方は {DailySummary}・{ReadingStreak}・{Combo} が持ち、ここはそれらを 1 行分そろえるだけ（行を描き直す応答が数字を取りこぼさないよう、集め方を 1 か所にする）
module TodayStatus
  extend ActiveSupport::Concern

  private

  def load_today_status
    @cards_count = Reading.card_count
    summary = DailySummary.new
    @today_count = summary.count
    @goal_articles = summary.goal
    @streak_days = ReadingStreak.days
    @combo_count = Combo.new.count
  end
end
