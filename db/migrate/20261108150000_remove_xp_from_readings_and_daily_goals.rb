# XP をやめ、完読した行そのものをカードとして残す（ADR 0020）。確定した数値は要らなくなる
class RemoveXpFromReadingsAndDailyGoals < ActiveRecord::Migration[8.1]
  def change
    remove_column :readings, :xp, :integer, default: 0, null: false
    remove_column :readings, :combo_multiplier, :decimal, precision: 3, scale: 1
    remove_column :daily_goals, :bonus_xp, :integer, default: 0, null: false
  end
end
