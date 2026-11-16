class CreateArticleJudgments < ActiveRecord::Migration[8.1]
  def change
    create_table :article_judgments do |t|
      t.references :article, null: false, foreign_key: true, index: { unique: true }
      t.float :originality
      t.float :depth
      t.float :practicality
      t.float :evidence
      t.float :insight
      t.float :applicability
      t.string :model
      t.integer :input_tokens
      t.float :cost
      t.datetime :judged_at
      t.datetime :failed_at
      t.string :error
      t.timestamps
    end
  end
end
