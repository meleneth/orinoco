# frozen_string_literal: true

class CreateD2rRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :d2r_runs do |t|
      t.string :game_id, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.datetime :run_started_at
      t.string :run_kind
      t.boolean :repeated, null: false, default: false
      t.integer :character_level
      t.string :area
      t.string :difficulty
      t.string :screen
      t.jsonb :terror_zones, null: false, default: []
      t.jsonb :steps, null: false, default: []
      t.jsonb :current_step, null: false, default: {}
      t.jsonb :events, null: false, default: []
      t.timestamps
    end
    add_index :d2r_runs, :game_id, unique: true
    add_index :d2r_runs, :started_at
    add_index :d2r_runs, [ :run_kind, :started_at ]
  end
end
