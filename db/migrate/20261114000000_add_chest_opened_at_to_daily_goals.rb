class AddChestOpenedAtToDailyGoals < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_goals, :chest_opened_at, :datetime
  end
end
