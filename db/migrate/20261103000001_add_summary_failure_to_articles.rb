class AddSummaryFailureToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :summary_failed_at, :datetime
    add_column :articles, :summary_error, :string
  end
end
