class CreateReadings < ActiveRecord::Migration[8.1]
  def change
    create_table :readings do |t|
      t.references :article, null: false, foreign_key: true, index: { unique: true }
      t.datetime :opened_at, null: false
      t.datetime :returned_at
      t.datetime :completed_at
      t.string :tier, null: false
      t.decimal :combo_multiplier, precision: 3, scale: 1
      t.integer :xp, null: false, default: 0
      t.text :note

      t.timestamps
    end
    add_index :readings, :completed_at
  end
end
