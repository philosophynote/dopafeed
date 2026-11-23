class CreateWeeklyComments < ActiveRecord::Migration[8.1]
  def change
    create_table :weekly_comments do |t|
      t.date :week_start, null: false, index: { unique: true }
      t.text :body
      t.string :model
      t.datetime :failed_at
      t.string :error
      t.timestamps
    end
  end
end
