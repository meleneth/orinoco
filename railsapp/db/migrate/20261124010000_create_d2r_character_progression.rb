# frozen_string_literal: true

class CreateD2rCharacterProgression < ActiveRecord::Migration[8.1]
  def change
    create_table :d2r_characters do |t|
      t.string :name, null: false
      t.string :character_class, null: false
      t.integer :level
      t.bigint :experience
      t.jsonb :stats, null: false, default: {}
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
      t.index [:name, :character_class], unique: true
    end
    add_reference :d2r_runs, :d2r_character, foreign_key: true
    create_table :d2r_character_observations do |t|
      t.references :d2r_character, null: false, foreign_key: true
      t.references :d2r_run, foreign_key: true
      t.string :fingerprint, null: false
      t.string :kind, null: false
      t.datetime :observed_at, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamps
      t.index :fingerprint, unique: true
      t.index [:d2r_character_id, :observed_at]
    end
  end
end
