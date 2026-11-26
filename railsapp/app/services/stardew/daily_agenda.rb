# frozen_string_literal: true

require_relative "dsl"

module Stardew
  class DailyAgenda
    SEASONS = %w[spring summer fall winter].freeze
    DAYS = %w[monday tuesday wednesday thursday friday saturday sunday].freeze
    ITEMS = { "wood" => "388", "parsnip" => "24", "green_bean" => "188",
              "cauliflower" => "190", "potato" => "192", "kale" => "250",
              "strawberry" => "400", "kale_seeds" => "477", "red_cabbage" => "266",
              "strawberry_seeds" => "745", "oak_resin" => "725",
              "fiberglass_rod" => "(T)FiberglassRod", "copper_pickaxe" => "(T)CopperPickaxe" }.freeze
    PRIORITY = { "critical" => 0, "high" => 1, "normal" => 2, "low" => 3 }.freeze

    def self.profile(root: File.expand_path("../../../config/stardew", __dir__))
      compiler = Dsl::Compiler.new(ruleset: "stardew-1.6")
      Dir.glob(File.join(root, "goals/*.rb")).sort.each { |file| compiler.load_file(file) }
      Dir.glob(File.join(root, "runs/*.rb")).sort.each { |file| compiler.load_file(file) }
      compiler.compile(:year_one_community_center)
    end

    def initialize(profile:, state:, history: [])
      @profile = profile
      @state = state
      @today = ordinal(state)
      @history = history.select { |entry| ordinal(entry) == @today }
      @goals = profile.fetch("goals")
    end

    def call
      return { tasks: [], tomorrow: [], warnings: [] } unless @today && @today <= ordinal(@profile.dig("run", "finishes"))

      tasks = @goals.values.filter_map do |goal|
        next unless due?(goal, @today)
        next if goal["when_needed"] && @goals.key?(goal["when_needed"]) &&
          evaluate(@goals.fetch(goal["when_needed"])).first == "complete" && goal["when_needed"] != goal["id"]

        status, evidence = evaluate(goal)
        dependencies = goal.fetch("requires").reject { |id| evaluate(@goals.fetch(id)).first == "complete" }
        status = "blocked" if status != "complete" && dependencies.any?
        { id: goal["id"], title: title(goal), status: status, evidence: evidence,
          dependencies: dependencies, preferred_time: goal["preferred_time"],
          priority: goal.fetch("priority", "normal"), strategies: goal.fetch("strategies"),
          target: goal.fetch("target") }
      end
      tasks.sort_by! { |task| [task[:status] == "complete" ? 1 : 0, order(task), PRIORITY.fetch(task[:priority]), task[:id]] }
      tomorrow = @goals.values.select { |goal| !goal["recurring"] && milestone(goal) == @today + 1 }
                       .reject { |goal| evaluate(goal).first == "complete" }.map { |goal| title(goal) }
      { tasks: tasks, tomorrow: tomorrow, warnings: warnings }
    end

    private

    def ordinal(date)
      return unless date.is_a?(Hash) && SEASONS.include?(date["season"]) &&
        date["year"].is_a?(Integer) && date["day"].is_a?(Integer)

      (date["year"] - 1) * 112 + SEASONS.index(date["season"]) * 28 + date["day"]
    end

    def milestone(goal)
      ordinal(goal["prefer_by"] || goal["deadline"])
    end

    def due?(goal, day)
      if goal["window"]
        return false unless (ordinal(goal["window"]["first"])..ordinal(goal["window"]["last"])).cover?(day)
      end
      if goal["recurring"]
        return false unless goal["every"].include?("day") || goal["every"].include?(DAYS[(day - 1) % 7])
        return false if goal["id"] == "pet_care" && day < 5
        return false if goal["id"] == "lucky_mining" && day < 5
        return false if goal["id"] == "spring_seeds" && day == 1
        return true
      end
      date = milestone(goal)
      date ? date <= day : %w[caroline_two_hearts caroline_sunroom tea_sapling_recipe].include?(goal["id"])
    end

    def order(task)
      return 0 if task[:id] == "crop_maintenance"
      return 1 if task[:strategies].include?("first_morning_outing")
      return 2 if task[:preferred_time]
      return 3 if %w[chest_house meet_villagers].include?(task[:id])

      4
    end

    def title(goal)
      target = goal.fetch("target")
      options = target.fetch("options")
      if options["crops"]
        return "Plant " + options["crops"].map { |name, count| "#{count} #{name.tr("_", " ")}" }.join(", ")
      end
      if target["subject"].end_with?("_skill")
        return "Reach #{target["subject"].delete_suffix("_skill").capitalize} #{target["quantity"]}"
      end
      goal["id"].tr("_", " ").capitalize
    end

    def inventory_count(subject)
      return unless @state["inventory"].is_a?(Array) && ITEMS.key?(subject)

      @state["inventory"].sum do |item|
        item["id"].to_s.delete_prefix("(O)") == ITEMS.fetch(subject) ? item["count"].to_i : 0
      end
    end

    def evaluate(goal)
      target = goal.fetch("target")
      subject = target.fetch("subject")
      quantity = target.fetch("quantity")
      options = target.fetch("options")
      return ["unknown", "Variable quantity requires planning"] if options["quantity_policy"] && !options["crops"]

      case target["type"]
      when "reach"
        if subject.end_with?("_skill")
          value = @state.dig("skills", subject.delete_suffix("_skill"))
          return progress(value, quantity, "skill level")
        elsif subject == "caroline_friendship"
          npc = friendship("Caroline")
          return progress(npc && npc["points"], quantity * 250, "friendship points")
        end
      when "talk"
        if subject == "introductions"
          return ["unknown", "Introduction quest targets are not yet observed"]
        end
        npc = friendship(subject)
        return ["complete", "Conversation observed today"] if npc && npc["talked_today"] == true
        return ["unknown", "Earlier introduction not retained"] if goal["id"] == "jas_introduction" && @today > 1
        return ["pending", "Conversation not observed today"] if @state["friendship"].is_a?(Array)
      when "plant"
        if options["crops"] && @state["crops"].is_a?(Array)
          counts = options["crops"].map do |name, needed|
            count = @state["crops"].count { |crop| !crop["dead"] && crop["harvest_id"].to_s.delete_prefix("(O)") == ITEMS[name] }
            [name, count, needed]
          end
          return [counts.all? { |_, count, needed| count >= needed } ? "complete" : "pending",
                  counts.map { |name, count, needed| "#{name.tr("_", " ")} #{count}/#{needed}" }.join(" · ")]
        end
      when "acquire", "reserve"
        return progress(@state["gold"], quantity, "gold") if subject == "gold"
        return progress(inventory_count(subject), quantity, "in backpack") unless options["budget"]
      when "maintain"
        if subject == "required_crops" && @state["crops"].is_a?(Array)
          crops = @state["crops"].reject { |crop| crop["dead"] }
          return progress(crops.count { |crop| crop["watered"] }, crops.size, "crops watered")
        elsif subject == "spring_onion_patch_check"
          return ["unknown", "Patch visit is not yet tracked; check south of Cindersap Forest"]
        end
      end
      ["unknown", "Completion not yet observable"]
    end

    def friendship(name)
      Array(@state["friendship"]).find { |npc| npc["npc"].to_s.casecmp?(name) }
    end

    def progress(value, target, units)
      return ["unknown", "Not observed"] unless value.is_a?(Numeric)

      [value >= target ? "complete" : "pending", "#{value}/#{target} #{units}"]
    end

    def warnings
      limit = @profile.dig("run", "unprotected_crop_limit")
      return [] unless limit && @state["crops"].is_a?(Array)

      return [] if @today > 6

      count = @state["crops"].count { |crop| !crop["dead"] }
      ["Before scarecrow coverage is verified, keep total live outdoor crops at #{limit} or fewer (currently #{count})."]
    end
  end
end
