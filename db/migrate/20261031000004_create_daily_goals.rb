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
