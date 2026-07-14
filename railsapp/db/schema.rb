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

ActiveRecord::Schema[8.1].define(version: 2026_07_13_123000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "affordance_configs", force: :cascade do |t|
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_affordance_configs_on_name", unique: true
  end

  create_table "diorama_edges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.uuid "diorama_id", null: false
    t.uuid "from_node_id", null: false
    t.string "kind", null: false
    t.uuid "to_node_id", null: false
    t.datetime "updated_at", null: false
    t.index ["diorama_id", "from_node_id", "to_node_id", "kind"], name: "idx_diorama_edges_unique_diorama_from_to_kind", unique: true
    t.index ["diorama_id", "from_node_id"], name: "index_diorama_edges_on_diorama_id_and_from_node_id"
    t.index ["diorama_id", "kind"], name: "index_diorama_edges_on_diorama_id_and_kind"
    t.index ["diorama_id", "to_node_id"], name: "index_diorama_edges_on_diorama_id_and_to_node_id"
    t.index ["diorama_id"], name: "index_diorama_edges_on_diorama_id"
    t.index ["from_node_id"], name: "index_diorama_edges_on_from_node_id"
    t.index ["to_node_id"], name: "index_diorama_edges_on_to_node_id"
  end

  create_table "diorama_nodes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.text "description"
    t.uuid "diorama_id", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.jsonb "validation_state", default: {}, null: false
    t.index ["data"], name: "index_diorama_nodes_on_data", using: :gin
    t.index ["diorama_id", "kind"], name: "index_diorama_nodes_on_diorama_id_and_kind"
    t.index ["diorama_id", "slug"], name: "index_diorama_nodes_on_diorama_id_and_slug", unique: true
    t.index ["diorama_id"], name: "index_diorama_nodes_on_diorama_id"
  end

  create_table "dioramas", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.string "version", default: "0.1.0", null: false
    t.string "visibility", default: "private", null: false
    t.index ["slug"], name: "index_dioramas_on_slug", unique: true
  end

  create_table "obs_configs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "host"
    t.integer "port"
    t.datetime "updated_at", null: false
  end

  create_table "official_wos_words", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "length", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "source"
    t.datetime "updated_at", null: false
    t.string "word", null: false
    t.index ["length"], name: "index_official_wos_words_on_length"
    t.index ["word"], name: "index_official_wos_words_on_word", unique: true
  end

  create_table "twitch_configs", force: :cascade do |t|
    t.string "channel_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "diorama_edges", "diorama_nodes", column: "from_node_id", on_delete: :cascade
  add_foreign_key "diorama_edges", "diorama_nodes", column: "to_node_id", on_delete: :cascade
  add_foreign_key "diorama_edges", "dioramas", on_delete: :cascade
  add_foreign_key "diorama_nodes", "dioramas", on_delete: :cascade
end
