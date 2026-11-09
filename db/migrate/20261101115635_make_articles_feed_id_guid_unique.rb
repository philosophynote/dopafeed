class MakeArticlesFeedIdGuidUnique < ActiveRecord::Migration[8.1]
  def change
    remove_index :articles, [ :feed_id, :guid ]
    add_index :articles, [ :feed_id, :guid ], unique: true
  end
end
