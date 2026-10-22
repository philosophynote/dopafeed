# Claude API 呼び出しの台帳。Claude::Budget が日次上限（dopamine.yml claude.daily_call_limit）を数える
class CreateClaudeApiCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :claude_api_calls do |t|
      t.string :purpose, null: false
      t.string :model, null: false

      t.timestamps
    end
    add_index :claude_api_calls, :created_at
  end
end
