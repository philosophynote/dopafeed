# [feed_id, guid] を一意に。FeedFetcher の重複排除の鍵で、同じフィードの Job が重なっても二重に入らない（Codex の指摘、PR #19）。
# guid が nil の行（seed など）は SQLite の一意索引で複数許される
class MakeArticlesFeedIdGuidUnique < ActiveRecord::Migration[8.1]
  def change
    remove_index :articles, [ :feed_id, :guid ]
    add_index :articles, [ :feed_id, :guid ], unique: true
  end
end
