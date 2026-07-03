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

ActiveRecord::Schema.define(version: 2026_07_02_130000) do

  create_table "admins", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admins_on_reset_password_token", unique: true
  end

  create_table "clients", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "company"
    t.string "name"
    t.string "tel"
    t.string "address"
    t.string "url"
    t.string "domain", default: "", null: false
    t.string "api_key", default: "", null: false
    t.string "stripe_customer_id"
    t.string "subscription_plan", default: "trial"
    t.string "subscription_status", default: "active"
    t.datetime "trial_ends_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "webhook_url"
    t.json "allowed_genres"
    t.json "embed_settings"
    t.index ["email"], name: "index_clients_on_email", unique: true
    t.index ["reset_password_token"], name: "index_clients_on_reset_password_token", unique: true
    t.index ["stripe_customer_id"], name: "index_clients_on_stripe_customer_id", unique: true
    t.index ["subscription_plan"], name: "index_clients_on_subscription_plan"
    t.index ["subscription_status"], name: "index_clients_on_subscription_status"
  end

  create_table "columns", force: :cascade do |t|
    t.string "title"
    t.string "file"
    t.string "choice"
    t.string "keyword"
    t.string "description"
    t.string "status", default: "draft"
    t.text "body"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "service_type", default: "cargo", null: false
    t.string "genre"
    t.string "code"
    t.string "article_type", default: "cluster", null: false
    t.integer "parent_id"
    t.integer "cluster_limit"
    t.text "prompt"
    t.string "sub_genre"
    t.string "generation_status", default: "idle", null: false
    t.float "quality_score", default: 0.0
    t.json "evaluation_metrics", default: "\"{}\""
    t.integer "client_id"
    t.index ["article_type"], name: "index_columns_on_article_type"
    t.index ["client_id"], name: "index_columns_on_client_id"
    t.index ["code"], name: "index_columns_on_code", unique: true
    t.index ["generation_status"], name: "index_columns_on_generation_status"
    t.index ["parent_id"], name: "index_columns_on_parent_id"
    t.index ["service_type"], name: "index_columns_on_service_type"
  end

  create_table "contracts", force: :cascade do |t|
    t.string "company"
    t.string "name"
    t.string "tel"
    t.string "email"
    t.string "address"
    t.string "url"
    t.string "service"
    t.string "period"
    t.string "message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "contracts_raws", force: :cascade do |t|
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at"
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "client_id", null: false
    t.integer "amount", null: false
    t.string "status", default: "pending", null: false
    t.text "description"
    t.string "stripe_payment_intent_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["client_id"], name: "index_payments_on_client_id"
    t.index ["status"], name: "index_payments_on_status"
    t.index ["stripe_payment_intent_id"], name: "index_payments_on_stripe_payment_intent_id", unique: true
  end

  create_table "service_genres", force: :cascade do |t|
    t.integer "client_id"
    t.string "key", null: false
    t.string "ja", null: false
    t.string "service_name"
    t.text "strong_points"
    t.json "hosts", default: []
    t.json "keywords", default: []
    t.json "images", default: []
    t.json "sub_categories", default: {}
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["client_id", "key"], name: "index_service_genres_on_client_id_and_key", unique: true
    t.index ["client_id"], name: "index_service_genres_on_client_id"
  end

  create_table "sites", force: :cascade do |t|
    t.string "name", null: false
    t.string "domain", null: false
    t.string "seo_title"
    t.string "contact_email"
    t.boolean "crm_enabled", default: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["domain"], name: "index_sites_on_domain", unique: true
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer "client_id", null: false
    t.string "plan_type", null: false
    t.string "status", default: "active", null: false
    t.datetime "trial_ends_at"
    t.string "stripe_subscription_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["client_id"], name: "index_subscriptions_on_client_id"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true
  end

  add_foreign_key "columns", "clients"
  add_foreign_key "payments", "clients"
  add_foreign_key "service_genres", "clients"
  add_foreign_key "subscriptions", "clients"
end
