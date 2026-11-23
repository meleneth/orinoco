# frozen_string_literal: true

class AddD2rRunDetectionData < ActiveRecord::Migration[8.1]
  def change
    add_column :d2r_runs, :run_confidence, :float
    add_column :d2r_runs, :run_evidence, :jsonb, null: false, default: []
    add_column :d2r_runs, :loot_sightings, :jsonb, null: false, default: []
    add_index :d2r_runs, :loot_sightings, using: :gin
  end
end
