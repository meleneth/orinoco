# frozen_string_literal: true

module Stardew
  class SpringFishing
    # Standard spring fish tank targets; remixed bundle parsing is separate.
    FISH = [
      ["142", "Carp", "Mountain", 600, 2600, :any],
      ["136", "Largemouth Bass", "Mountain", 600, 1900, :any],
      ["700", "Bullhead", "Mountain", 600, 2600, :any],
      ["145", "Sunfish", "Town", 600, 1900, :sun],
      ["143", "Catfish", "Town", 600, 2400, :rain],
      ["706", "Shad", "Town", 900, 2600, :rain],
      ["128", "Pufferfish", "Beach", 1200, 1600, :summer],
      ["131", "Sardine", "Beach", 600, 1900, :any],
      ["147", "Herring", "Beach", 600, 2600, :any],
      ["148", "Eel", "Beach", 1600, 2600, :rain],
      ["132", "Bream", "Town", 1800, 2600, :any]
    ].reject { |fish| %w[128 147].include?(fish.first) }.freeze

    def initialize(state)
      @state = state
    end

    def rod?
      (Array(@state["tools"]) + Array(@state["inventory"])).any? do |item|
        [item["id"], item["name"]].compact.any? { |value| value.match?(/BambooPole|TrainingRod|FiberglassRod|IridiumRod|AdvancedIridiumRod|bamboo pole|fishing rod|training rod|fiberglass rod|iridium rod/i) }
      end
    end

    def call
      return unless rod? && @state["season"] == "spring"
      clock = @state["time"].to_i
      return if clock < 600 || clock >= 2400

      items = Array(@state["inventory"]) + Array(@state["chests"]).flat_map { |chest| Array(chest["items"]) }
      owned = items.select { |item| item["count"].to_i.positive? }.map { |item| item["id"].to_s.delete_prefix("(O)") }
      rain = @state["raining"] == true
      available = FISH.select do |id, _, _, start, finish, weather|
        !owned.include?(id) && clock >= start && clock < finish &&
          (weather == :any || weather == (rain ? :rain : :sun))
      end
      location = if rain
        clock >= 1600 && available.any? { |f| f[0] == "148" } ? "Beach" : "Town"
      elsif @state["location"] == "Beach" && clock < 1900 && available.any? { |f| f[2] == "Beach" }
        "Beach"
      elsif clock >= 1800 && available.any? { |f| f[0] == "132" }
        "Town"
      else
        "Mountain"
      end
      targets = available.select { |f| f[2] == location }.map { |f| f[1] }
      directions = {
        "Mountain" => "Fish in the mountain lake east of Robin's Carpenter's Shop; cast away from shore.",
        "Beach" => "Fish from the ocean pier near Willy's shop, south of town.",
        "Town" => "Fish in the river running through Pelican Town, near the bridge."
      }.fetch(location)
      level = @state.dig("skills", "fishing").to_i
      { title: "Fish at #{location == 'Mountain' ? 'the mountain lake' : location == 'Beach' ? 'the ocean' : 'the town river'}",
        directions: directions, targets: targets,
        evidence: [targets.any? ? "Keep one each: #{targets.join(', ')}." : "Fish for income and XP; store useful catches.",
                   rain && location == "Town" && level < 3 ? "Catfish are difficult with the bamboo pole; keep easier Shad and Bream too." : nil,
                   level < 2 ? "Reach Fishing 2 to unlock the 1,800g Fiberglass Rod." : "Save 1,800g for the Fiberglass Rod if not already owned."].compact.join(" "),
        target: { "type" => "fish", "subject" => "fishing", "options" => {} } }
    end
  end
end
