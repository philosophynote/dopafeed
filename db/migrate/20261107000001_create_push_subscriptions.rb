class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.string :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.string :user_agent
      t.date :digest_sent_on
      t.date :streak_warning_sent_on

      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true
  end
end
