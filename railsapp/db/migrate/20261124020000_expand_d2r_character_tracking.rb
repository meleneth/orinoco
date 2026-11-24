# frozen_string_literal: true

class ExpandD2rCharacterTracking < ActiveRecord::Migration[8.1]
  def up
    add_column :d2r_characters, :identity_key, :string
    add_column :d2r_characters, :ladder, :boolean
    add_column :d2r_characters, :hardcore, :boolean
    add_column :d2r_characters, :expansion, :boolean
    add_column :d2r_characters, :season, :string
    add_column :d2r_characters, :observed_created_at, :datetime

    execute <<~SQL.squish
      UPDATE d2r_characters
      SET identity_key = 'legacy-' || id::text || '-' || encode(gen_random_bytes(8), 'hex')
      WHERE identity_key IS NULL
    SQL
    change_column_null :d2r_characters, :identity_key, false
    remove_index :d2r_characters, column: [:name, :character_class]
    add_index :d2r_characters, :identity_key, unique: true
    add_index :d2r_characters, [:name, :character_class]

    create_table :d2r_activities do |t|
      t.references :d2r_run, null: false, foreign_key: true
      t.references :d2r_character, foreign_key: true
      t.string :kind, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.float :confidence
      t.jsonb :evidence, null: false, default: []
      t.string :boundary_key, null: false
      t.timestamps
      t.index [:d2r_run_id, :kind, :started_at], name: "idx_d2r_activities_run_kind_started"
      t.index :boundary_key, unique: true
    end

    create_table :d2r_time_intervals do |t|
      t.references :d2r_run, foreign_key: true
      t.references :d2r_character, foreign_key: true
      t.string :kind, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.decimal :seconds, precision: 14, scale: 3, null: false
      t.string :fingerprint, null: false
      t.jsonb :evidence, null: false, default: {}
      t.timestamps
      t.index :fingerprint, unique: true
      t.index [:d2r_character_id, :started_at], name: "idx_d2r_time_intervals_character_started"
      t.index [:d2r_run_id, :started_at], name: "idx_d2r_time_intervals_run_started"
    end

    create_table :d2r_act_milestones do |t|
      t.references :d2r_character, null: false, foreign_key: true
      t.string :difficulty, null: false
      t.integer :act, null: false
      t.string :status, null: false
      t.datetime :observed_at, null: false
      t.jsonb :evidence, null: false, default: {}
      t.timestamps
      t.index [:d2r_character_id, :difficulty, :act], unique: true,
        name: "idx_d2r_act_milestones_character_difficulty_act"
    end
  end

  def down
    drop_table :d2r_act_milestones
    drop_table :d2r_time_intervals
    drop_table :d2r_activities
    remove_index :d2r_characters, :identity_key
    remove_index :d2r_characters, column: [:name, :character_class]
    add_index :d2r_characters, [:name, :character_class], unique: true
    remove_columns :d2r_characters, :identity_key, :ladder, :hardcore, :expansion,
      :season, :observed_created_at
  end
end
