class AddDismissedAtToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :dismissed_at, :datetime
    add_index :articles, :dismissed_at
  end
end
