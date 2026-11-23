class AddStateToPersonaComments < ActiveRecord::Migration[8.1]
  def change
    change_column_null :persona_comments, :body, true
    add_column :persona_comments, :failed_at, :datetime
    add_column :persona_comments, :error, :string
  end
end
