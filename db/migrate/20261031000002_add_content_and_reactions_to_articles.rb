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
