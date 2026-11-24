# frozen_string_literal: true

module D2r
  # Replays durable observations rather than requiring a boss-death screenshot.
  # A game ending is not necessarily a successful farming objective.
  class RunOutcome
    TOWNS = ["Rogue Encampment", "Lut Gholein", "Kurast Docks", "Pandemonium Fortress", "Harrogath"].freeze
    COUNTESS_FLOOR = "Tower Cellar Level 5"
    EXIT_EVENTS = %w[d2r.game.ended d2r.character.selection.visible d2r.character.creation.visible d2r.game.creation.visible].freeze

    def self.call(run)
      return run.ended_at ? "finished" : "in_progress" unless run.run_kind == "countess"

      reached = false
      died = false
      events = run.events.sort_by { |event| event["at"].to_s }
      events.each do |event|
        type = event["type"]
        area = event.dig("payload", "area")
        reached = true if type == "d2r.area.changed" && area == COUNTESS_FLOOR
        died = true if type == "d2r.player.died"
        boundary = EXIT_EVENTS.include?(type) || (type == "d2r.area.changed" && TOWNS.include?(area))
        return "completed" if boundary && reached && !died
      end

      # Older records may retain the floor in their inferred route/splits even
      # when the original area event has aged out of the bounded archive.
      reached ||= run.run_evidence.include?(COUNTESS_FLOOR) ||
        run.steps.any? { |step| step["name"] == COUNTESS_FLOOR } ||
        run.current_step["name"] == COUNTESS_FLOOR || run.area == COUNTESS_FLOOR
      exited = run.ended_at || TOWNS.include?(run.area) ||
        %w[character_select character_creation game_creation].include?(run.screen)
      return "failed" if died
      return "completed" if reached && exited
      return "incomplete" if run.ended_at

      "in_progress"
    end
  end
end
