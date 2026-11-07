class CreateArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :articles do |t|
      t.references :feed, null: false, foreign_key: true
      t.string :title, null: false
      t.string :url, null: false
      t.text :summary
      t.datetime :published_at

      t.timestamps
    end
    add_index :articles, :url, unique: true
    add_index :articles, :published_at
  end
end
