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
