# frozen_string_literal: true

class CreateOfficialWosWords < ActiveRecord::Migration[8.1]
  def change
    create_table :official_wos_words do |t|
      t.string :word, null: false
      t.integer :length, null: false
      t.string :source
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :official_wos_words, :word, unique: true
    add_index :official_wos_words, :length
  end
end