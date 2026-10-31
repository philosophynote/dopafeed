# guid: feedjira の entry_id（url と合わせて重複排除）。content: readability の本文（要約の入力、推定読了時間の元）。
# liked_at / bookmarked_at: 一人用なので記事に直接残す（ADR 0006）。
class AddContentAndReactionsToArticles < ActiveRecord::Migration[8.1]
  def change
    change_table :articles, bulk: true do |t|
      t.string :guid
      t.text :content
      t.datetime :liked_at
      t.datetime :bookmarked_at
    end
    add_index :articles, [ :feed_id, :guid ]
    add_index :articles, :liked_at
    add_index :articles, :bookmarked_at
  end
end
