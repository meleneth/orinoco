# frozen_string_literal: true

class RenameDefaultD2rSeason < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE seasons
      SET name = 'Ladder Season 16', updated_at = CURRENT_TIMESTAMP
      FROM game_definitions
      WHERE seasons.game_definition_id = game_definitions.id
        AND game_definitions.name = 'Diablo II: Resurrected'
        AND seasons.name = 'Season 1'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE seasons
      SET name = 'Season 1', updated_at = CURRENT_TIMESTAMP
      FROM game_definitions
      WHERE seasons.game_definition_id = game_definitions.id
        AND game_definitions.name = 'Diablo II: Resurrected'
        AND seasons.name = 'Ladder Season 16'
    SQL
  end
end
