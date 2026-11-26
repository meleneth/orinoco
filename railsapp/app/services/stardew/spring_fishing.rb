# frozen_string_literal: true

require_relative "fish_liquidation"

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

    def owns_rod?(pattern)
      (Array(@state["tools"]) + Array(@state["inventory"])).any? do |item|
        [item["id"], item["name"]].compact.any? { |value| pattern.match?(value) }
      end
    end

    def training_rod?
      owns_rod?(/Training\s*Rod|\(T\)TrainingRod/i)
    end

    def upgraded_rod?
      owns_rod?(/Fiberglass\s*Rod|Iridium\s*Rod/i)
    end

    def investment_action
      return unless rod? && @state["year"] == 1 && @state["season"] == "spring"
      clock = @state["time"].to_i
      return unless clock >= 900 && clock < 1700
      level = @state.dig("skills", "fishing").to_i
      cash = @state["gold"].to_i
      return if upgraded_rod?

      if level >= 2 && cash >= 1800
        bait = [[(cash - 1800) / 5, 40].min, 0].max
        return action("Buy the Fiberglass Rod", "Spend 1,800g on the rod#{bait.positive? ? " and #{bait} bait (#{bait * 5}g); attach bait to the rod" : "; buy bait as soon as you can afford it"}.")
      end
      liquidation = FishLiquidation.new(@state).call
      if level >= 2 && liquidation[:liquid] >= 1800 && liquidation[:net].positive?
        return action("Sell surplus fish to fund the Fiberglass Rod", "Sell only the quantities shown in the liquidation panel; then buy the rod and affordable bait.")
      end
      if level < 5 && !training_rod? && cash >= 25
        return action("Buy the Training Rod for 25g", "Use it for easy catches and perfect-catch XP until the Fiberglass Rod is affordable.")
      end
      nil
    end

    def action(title, evidence)
      { title: title, evidence: evidence, directions: "Go to Willy's Fish Shop on the ocean pier, south of town. Buy before 5 PM.",
        target: { "type" => "purchase", "subject" => "fishing_equipment", "options" => {} } }
    end

    def call
      return unless rod? && @state["season"] == "spring"
      clock = @state["time"].to_i
      return if clock < 600 || clock >= 2400

      investment = investment_action
      return investment if investment

      items = Array(@state["inventory"]) + Array(@state["chests"]).flat_map { |chest| Array(chest["items"]) }
      owned = items.select { |item| item["count"].to_i.positive? }.map { |item| item["id"].to_s.delete_prefix("(O)") }
      rain = @state["raining"] == true
      available = FISH.select do |id, _, _, start, finish, weather|
        !owned.include?(id) && clock >= start && clock < finish &&
          (weather == :any || weather == (rain ? :rain : :sun))
      end
      training = training_rod? && !upgraded_rod? && @state.dig("skills", "fishing").to_i < 5
      # The training rod only catches fish with difficulty below 50.
      available = available.reject { |f| %w[136 143 148].include?(f[0]) } if training
      location = if @state["year"] == 1 && @state["day"] == 2
        "Beach"
      elsif rain
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
                   training ? "Equip the Training Rod; aim for perfect catches." : nil,
                   !training_rod? && !upgraded_rod? && level < 5 ? "If short of 25g, catch and sell surplus fish to Willy before 5 PM; buy the Training Rod." : nil,
                   !upgraded_rod? ? (level < 2 ? "Reach Fishing 2 to unlock the 1,800g Fiberglass Rod." : "Save 1,800g for the Fiberglass Rod; 2,000g buys the rod and 40 bait.") : "Use bait with your upgraded rod.",
                   @state["day"].to_i <= 13 ? "Do not buy the Iridium Rod before the strawberry investment." : nil].compact.join(" "),
        target: { "type" => "fish", "subject" => "fishing", "options" => {} } }
    end
  end
end
