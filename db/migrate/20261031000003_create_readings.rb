# 読了は 1 記事 1 行（ADR 0006）。「読む」のタップで行を作り（opened_at + 抽選結果 tier）、
# 戻ってきたら returned_at / completed_at / xp を埋める。tier は名前だけ。倍率・確率は yml から導く。
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
