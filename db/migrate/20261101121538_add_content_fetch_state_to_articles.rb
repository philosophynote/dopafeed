class AddContentFetchStateToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :content_fetched_at, :datetime
    add_column :articles, :content_error, :string
  end
end
