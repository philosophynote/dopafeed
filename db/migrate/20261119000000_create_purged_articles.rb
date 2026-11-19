class CreatePurgedArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :purged_articles do |t|
      # 目印を知らない版へ戻しても購読を消せるよう、行の後始末を DB に持たせる。
      t.references :feed, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :guid
      t.string :url, null: false
      t.string :reason, null: false
      t.datetime :purged_at, null: false
      t.index %i[feed_id guid], unique: true
      t.index :url, unique: true
    end
  end
end
