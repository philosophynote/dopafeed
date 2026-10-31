# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_31_000004) do
  create_table "articles", force: :cascade do |t|
    t.integer "feed_id", null: false
    t.string "title", null: false
    t.string "url", null: false
    t.text "summary"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "guid"
    t.text "content"
    t.datetime "liked_at"
    t.datetime "bookmarked_at"
    t.index [ "bookmarked_at" ], name: "index_articles_on_bookmarked_at"
    t.index [ "feed_id", "guid" ], name: "index_articles_on_feed_id_and_guid"
    t.index [ "feed_id" ], name: "index_articles_on_feed_id"
    t.index [ "liked_at" ], name: "index_articles_on_liked_at"
    t.index [ "published_at" ], name: "index_articles_on_published_at"
    t.index [ "url" ], name: "index_articles_on_url", unique: true
  end

  create_table "claude_api_calls", force: :cascade do |t|
    t.string "purpose", null: false
    t.string "model", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "created_at" ], name: "index_claude_api_calls_on_created_at"
  end

  create_table "daily_goals", force: :cascade do |t|
    t.date "day", null: false
    t.datetime "achieved_at"
    t.integer "bonus_xp", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "day" ], name: "index_daily_goals_on_day", unique: true
  end

  create_table "feeds", force: :cascade do |t|
    t.string "title", null: false
    t.string "url", null: false
    t.string "site_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_fetched_at"
    t.string "last_error"
    t.string "etag"
    t.string "last_modified"
    t.index [ "url" ], name: "index_feeds_on_url", unique: true
  end

  create_table "readings", force: :cascade do |t|
    t.integer "article_id", null: false
    t.datetime "opened_at", null: false
    t.datetime "returned_at"
    t.datetime "completed_at"
    t.string "tier", null: false
    t.decimal "combo_multiplier", precision: 3, scale: 1
    t.integer "xp", default: 0, null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "article_id" ], name: "index_readings_on_article_id", unique: true
    t.index [ "completed_at" ], name: "index_readings_on_completed_at"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "user_id" ], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "email_address" ], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "articles", "feeds"
  add_foreign_key "readings", "articles"
  add_foreign_key "sessions", "users"
end
