class AddCommentsRequestedAtToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :comments_requested_at, :datetime
  end
end
