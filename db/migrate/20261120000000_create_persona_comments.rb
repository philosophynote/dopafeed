class CreatePersonaComments < ActiveRecord::Migration[8.1]
  def change
    create_table :persona_comments do |t|
      t.references :article, null: false, foreign_key: { on_delete: :cascade }
      t.string :persona_id, null: false
      t.text :body, null: false
      t.timestamps
    end
    add_index :persona_comments, %i[article_id persona_id], unique: true

    add_column :articles, :comments_failed_at, :datetime
    add_column :articles, :comments_error, :string
  end
end
