# 1 日（daily_goal.reset_hour 基準）につき 1 行。宝箱を開いたら achieved_at。
# bonus_xp は鍵 daily_goal.bonus_xp が入るまで 0 のまま。
class CreateDailyGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_goals do |t|
      t.date :day, null: false
      t.datetime :achieved_at
      t.integer :bonus_xp, null: false, default: 0

      t.timestamps
    end
    add_index :daily_goals, :day, unique: true
  end
end
