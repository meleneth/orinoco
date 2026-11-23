# frozen_string_literal: true

class CreateGameCatalogAndLootDrops < ActiveRecord::Migration[8.1]
  def change
    create_table :game_definitions do |t|
      t.string :name, null: false
      t.string :publisher, null: false
      t.integer :year, null: false
      t.string :link, null: false
      t.timestamps
    end
    add_index :game_definitions, %i[name publisher year], unique: true

    create_table :seasons do |t|
      t.references :game_definition, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :active, null: false, default: false
      t.timestamps
    end
    add_index :seasons, %i[game_definition_id name], unique: true
    add_index :seasons, :game_definition_id, unique: true, where: "active", name: "index_seasons_on_active_game"

    create_table :loot_drops do |t|
      t.references :season, null: false, foreign_key: true
      t.references :d2r_run, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :name, null: false
      t.string :confidence, null: false
      t.datetime :observed_at, null: false
      t.string :event_fingerprint, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :loot_drops, :event_fingerprint, unique: true
    add_index :loot_drops, %i[season_id observed_at]
  end
end
