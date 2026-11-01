# Unit 3 の取得 Job が書く。last_error が nil なら前回は成功（Feeds 画面の赤字はここから）。
# etag / last_modified は条件付き GET 用。
class AddFetchStateToFeeds < ActiveRecord::Migration[8.1]
  def change
    change_table :feeds, bulk: true do |t|
      t.datetime :last_fetched_at
      t.string :last_error
      t.string :etag
      t.string :last_modified
    end
  end
end
