# frozen_string_literal: true

require_relative "dsl"
require_relative "gift_advisor"
require_relative "opening_shopping"
require_relative "route_guidance"
require_relative "spring_fishing"

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
      @gift_advice = build_gift_advice
      @shopping = OpeningShopping.new(state).call
      @fishing = SpringFishing.new(state)
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
      tasks.sort_by! { |task| [task[:status] == "complete" ? 1 : 0, order(task), task[:preferred_time] || "99:99", task[:target].fetch("options").fetch("route_index", 999), PRIORITY.fetch(task[:priority]), task[:id]] }
      tasks.each { |task| task[:directions] = RouteGuidance.describe(task, @state) }
      tomorrow = @goals.values.select { |goal| !goal["recurring"] && milestone(goal) == @today + 1 }
                       .reject { |goal| evaluate(goal).first == "complete" }.map { |goal| title(goal) }
      { tasks: tasks, tomorrow: tomorrow, warnings: warnings, next_action: next_action(tasks),
        blockers: blockers(tasks), relationships: relationship_status, upcoming_introduction: upcoming_introduction(tasks), shopping: @shopping, fishing: @fishing.call, liquidation: @fishing.rod? ? FishLiquidation.new(@state).call : nil }
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
      date ? date <= day : %w[linus_four_hearts caroline_two_hearts caroline_sunroom tea_sapling_recipe].include?(goal["id"])
    end

    def order(task)
      return -2 if task[:id] == "first_chest_wood"
      return -1 if task[:id] == "chest_house"
      return 0 if task[:id] == "crop_maintenance"
      return 1 if task[:id] == "spring_onion_check"
      return 2 if task[:id] == "spring_onions"
      return 3 if task[:preferred_time]
      return 4 if task[:strategies].include?("priority_friendship")
      return 4 if %w[chest_house meet_villagers].include?(task[:id])

      5
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
      return "Chop 50 wood for your first chest" if goal["id"] == "first_chest_wood"
      return "Craft and place your first chest" if goal["id"] == "chest_house"
      return "Check spring onion patches in southern Cindersap Forest" if goal["id"] == "spring_onion_check"
      if target["type"] == "talk" && target["subject"] != "introductions"
        return "Talk to #{target["subject"].capitalize}"
      elsif target["type"] == "gift" && options["period"] == "week"
        advice = @gift_advice[target["subject"]]
        return advice ? "#{target["subject"].capitalize}: #{advice[:text]}" : "Give #{target["subject"].capitalize} a gift"
      end
      goal["id"].tr("_", " ").capitalize
    end

    def inventory_count(subject)
      return unless @state["inventory"].is_a?(Array) && ITEMS.key?(subject)

      @state["inventory"].sum do |item|
        item["id"].to_s.delete_prefix("(O)") == ITEMS.fetch(subject) ? item["count"].to_i : 0
      end
    end

    # The farmhouse starter parcel is also a Chest in the game API.
    # Only trust the filtered player-owned storage collection or crafting evidence.
    def placed_storage_chest?
      if @state["chests"].is_a?(Array)
        return @state["chests"].any? { |chest| %w[Farm FarmHouse].include?(chest["location"]) && !Array(chest["items"]).any? { |item| item["id"] == "(O)472" && item["count"].to_i == 15 } } if !@state["recipes"].is_a?(Hash)
        return @state["chests"].any? { |chest| %w[Farm FarmHouse].include?(chest["location"]) } && (@state["recipes"].fetch("Chest", 0).to_i > 0 || @today > 1)
      end
      @state["house_chest"] == true && @state.dig("recipes", "Chest").to_i > 0
    end

    def evaluate(goal)
      target = goal.fetch("target")
      subject = target.fetch("subject")
      quantity = target.fetch("quantity")
      options = target.fetch("options")
      if Array(@state["completed_milestones"]).include?(goal["id"]) && !goal["recurring"] && goal["id"] != "first_chest_wood"
        return ["complete", "Previously observed milestone"]
      end
      if goal["id"] == "first_chest_wood"
        wood = inventory_count("wood")
        wood = [wood.to_i, @state["wood_peak_today"]].max if @state["wood_peak_today"].is_a?(Integer)
        return ["complete", "Chest crafted or placed"] if @state.dig("recipes", "Chest").to_i > 0 || placed_storage_chest? || Array(@state["inventory"]).any? { |item| item["id"] == "(BC)130" }
        return progress(wood, 50, "wood in backpack")
      elsif goal["id"] == "chest_house"
        return ["complete", "Chest placed at farmhouse or farm"] if placed_storage_chest?
        return ["pending", "Place the crafted chest near the house"] if Array(@state["inventory"]).any? { |item| item["id"] == "(BC)130" }
        return ["pending", "Craft a chest from 50 wood"] if inventory_count("wood").to_i >= 50
        return ["unknown", "Chest placement not yet observed"] unless @state.key?("house_chest")
        return ["pending", "Collect 50 wood first"]
      elsif goal["id"] == "spring_onion_check"
        return ["complete", "Patch visited today"] if @state["spring_onion_patch_checked"] == true
        return ["pending", "First morning outing; check the patch even if empty"]
      elsif goal["id"] == "spring_onions"
        return ["complete", "Patch checked; no onions remaining"] if @state["spring_onion_patch_checked"] == true && @state["spring_onions"] == []
        return ["pending", "Pick available onions for energy and gifts"] if @state["spring_onion_patch_checked"] == true && Array(@state["spring_onions"]).any?
        return ["unknown", "Check the patch first"]
      end
      if subject == "scarecrow" && @state["scarecrows"].is_a?(Array)
        return progress(@state["scarecrows"].size, 1, "placed scarecrows")
      elsif subject == "mine_floor" || subject == "mine_progress"
        return progress(@state["mine_floor"], quantity, "mine floor") unless options["quantity_policy"]
      elsif subject == "gatherer_profession" && @state["professions"].is_a?(Array)
        return [@state["professions"].include?(13) ? "complete" : "pending", "Choose Gatherer at Foraging 5"]
      elsif subject == "tea_sapling_recipe" && @state["recipes"].is_a?(Hash)
        return [@state["recipes"].key?("Tea Sapling") ? "complete" : "pending", "Check Caroline's recipe mail"]
      elsif subject == "training_rod"
        return [@fishing.training_rod? || @fishing.upgraded_rod? || @state.dig("skills", "fishing").to_i >= 5 ? "complete" : "pending", "Buy the 25g Training Rod from Willy before 5 PM"]
      elsif subject == "fiberglass_rod"
        return [@fishing.upgraded_rod? ? "complete" : "pending", "Fishing 2 and 1,800g required"]
      elsif subject == "fishing_rod"
        return [@fishing.rod? ? "complete" : "pending", "Visit the beach south of town between 6 AM and 5 PM to receive Willy’s bamboo pole"]
      elsif target["type"] == "build" && subject == "chest" && @state["chests"].is_a?(Array)
        maps = { "ocean_fishing" => "Beach", "mountain_fishing" => "Mountain", "mines" => "Mine" }
        map = maps[options["location"]]
        return progress(@state["chests"].count { |chest| chest["location"] == map }, 1, "placed chests at #{map}") if map
      end
      return ["unknown", "Variable quantity requires planning"] if options["quantity_policy"] && !options["crops"]

      case target["type"]
      when "reach"
        if subject.end_with?("_skill")
          value = @state.dig("skills", subject.delete_suffix("_skill"))
          return progress(value, quantity, "skill level")
        elsif %w[caroline_friendship linus_friendship].include?(subject)
          npc = friendship(subject.delete_suffix("_friendship"))
          return progress(npc && npc["points"], quantity * 250, "friendship points")
        end
      when "talk"
        if subject == "introductions"
          required = @goals.values.select { |entry| entry.dig("target", "options", "introduction") && !entry.dig("target", "options", "optional") }
          count = required.count { |entry| introduced?(entry.dig("target", "subject")) }
          return ["complete", "All tracked introductions complete"] if count == required.size && required.any?
          return ["pending", "#{count}/#{required.size} tracked introductions"]
        end
        npc = friendship(subject)
        if options["introduction"]
          return ["complete", "Previously introduced"] if introduced?(subject)
          return ["pending", "Introduction still outstanding"]
        end
        return ["complete", "Conversation observed today"] if npc && npc["talked_today"] == true
        return ["unknown", "Earlier introduction not retained"] if goal["id"] == "jas_introduction" && @today > 1
        return ["pending", "Conversation not observed today"] if @state["friendship"].is_a?(Array)
      when "gift"
        if options["period"] == "week"
          npc = friendship(subject)
          return ["pending", "Introduce yourself first; #{@gift_advice.dig(subject, :text)}"] unless npc
          return ["unknown", "Gift counters not observed"] unless npc["gifts_this_week"].is_a?(Integer) && npc["gifts_today"].is_a?(Integer)
          count = npc["gifts_this_week"]
          return ["complete", "#{count}/#{quantity} gifts this week"] if count >= quantity
          return ["deferred", "#{count}/#{quantity} this week; already gifted today"] if npc["gifts_today"] >= options.fetch("daily_limit", 1)
          return ["pending", "#{count}/#{quantity} this week; gift available today"]
        end
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
        if options["budget"] && subject == "kale_seeds"
          return ["complete", "Opening seed budget spent"] if @shopping && @shopping[:complete]
          return ["pending", "Buy kale only after required seeds and the 28g Day 2 rod reserve"]
        end
        return progress(inventory_count(subject), quantity, "in backpack") unless options["budget"]
      when "maintain"
        if subject == "required_crops" && @state["crops"].is_a?(Array)
          crops = @state["crops"].reject { |crop| crop["dead"] }
          ready = crops.count { |crop| crop["ready"] == true }
          return ["pending", "Harvest #{ready} ready crops"] if ready.positive?
          return progress(crops.count { |crop| crop["watered"] }, crops.size, "crops watered")
        elsif subject == "spring_onion_patch_check"
          return ["unknown", "Patch visit is not yet tracked; check south of Cindersap Forest"]
        end
      end
      ["unknown", "Completion not yet observable"]
    end

    def upcoming_introduction(tasks)
      return unless @today == 1

      tasks.find { |task| task[:status] == "pending" && task[:target].dig("options", "introduction") && task[:preferred_time] && task[:preferred_time].delete(":").to_i >= @state["time"].to_i }
    end

    def next_action(tasks)
      candidates = tasks.select { |task| task[:status] == "pending" ||
        (task[:status] == "unknown" && %w[spring_onion_check spring_onions chest_house opening_kale_seeds].include?(task[:id])) }
      # Milestones measure outcomes, not executable instructions.
      candidates.reject! { |task| task[:target]["type"] == "reach" || task[:target]["subject"] == "introductions" || %w[training_rod fiberglass_rod].include?(task[:id]) }
      # Avoid pinning the whole day to an unobservable morning task.
      clock = @state["time"].to_i
      candidates.reject! { |task| task[:id] == "chest_house" && inventory_count("wood").to_i < 50 && !Array(@state["inventory"]).any? { |item| item["id"] == "(BC)130" } }
      candidates.reject! { |task| task[:id] == "spring_onions" && @state["spring_onion_patch_checked"] != true }
      candidates.reject! { |task| task[:strategies].include?("first_morning_outing") && clock >= 1100 && !@state.key?("spring_onion_patch_checked") }
      candidates.reject! { |task| task[:id] == "first_chest_wood" && @today > 1 && !@state.key?("house_chest") }
      if @today == 1 && %w[Farm FarmHouse].include?(@state["location"]) && clock < 1000
        opening_chest = candidates.find { |task| %w[first_chest_wood chest_house].include?(task[:id]) }
        return opening_chest if opening_chest
      end
      if @today >= 2 && !@fishing.rod? && clock >= 600 && clock < 1700
        rod = candidates.find { |task| task[:id] == "fishing_rod" }
        return rod.merge(title: "Meet Willy and collect your bamboo pole", directions: "Walk south out of Pelican Town to the beach; head toward the fish shop on the pier.") if rod
      end
      if @today >= 2 && (investment = @fishing.investment_action)
        return investment
      end
      if @shopping && @shopping[:at_shop] && @shopping[:purchases].any?
        task = candidates.find { |entry| entry[:id] == "opening_kale_seeds" }
        return task.merge(title: "Buy seeds at Pierre's", evidence: "Follow the live shopping checklist below.") if task
      end
      local = Array(@state["npcs"]).select { |npc| npc["location"] == @state["location"] }
      nearby = candidates.filter_map do |task|
        next unless %w[talk gift].include?(task[:target]["type"])
        npc = local.find { |entry| entry["npc"].to_s.casecmp?(task[:target]["subject"]) }
        next unless npc

        distance = (npc["x"].to_i - @state["tile_x"].to_i).abs + (npc["y"].to_i - @state["tile_y"].to_i).abs
        [task, distance]
      end
      close = nearby.select { |_, distance| distance <= 12 }.min_by { |task, distance| [distance, task[:target]["type"] == "talk" ? 0 : 1, task[:id]] }
      return close.first if close
      upcoming = upcoming_introduction(tasks)
      return upcoming if upcoming && clock >= 1000 && clock < 1100
      # Preserve morning chores before the route; after 11 the rendezvous takes priority.
      return candidates.first if clock < 1000 && candidates.first && order(candidates.first) <= 2
      return nearby.min_by { |task, distance| [distance, task[:id]] }.first if nearby.any?
      if @today == 1 && clock >= 1000
        introductions = candidates.select { |task| task[:target].dig("options", "introduction") }
        # Missed rendezvous remain outstanding; a live location is better than a stale timestamp.
        introductions.sort_by! do |task|
          preferred = task[:preferred_time].to_s.delete(":").to_i
          [preferred >= clock - 100 ? 0 : 1, task[:preferred_time] || "99:99"]
        end
        return introductions.first if introductions.any?
      end
      if @today >= 2 && (fishing = @fishing.call)
        chores = candidates.find { |task| task[:id] == "crop_maintenance" && @state["location"] == "Farm" }
        return chores if chores
        onion = candidates.find { |task| task[:id] == "spring_onion_check" && clock < 900 }
        return onion if onion
        return fishing
      end
      candidates.first
    end

    def blockers(tasks)
      tasks.filter_map do |task|
        next unless task[:status] == "blocked"
        next unless task[:priority] == "critical" || task[:priority] == "high" || task[:id] == "expand_kale"

        { title: task[:title], reason: "Requires: #{task[:dependencies].map { |id| id.tr("_", " ") }.join(", ")}" }
      end
    end

    def relationship_status
      %w[Linus Caroline].map do |name|
        npc = friendship(name)
        { name: name, points: npc && npc["points"], talked_today: npc && npc["talked_today"],
          gifts_today: npc && npc["gifts_today"], gifts_this_week: npc && npc["gifts_this_week"],
          target_hearts: name == "Linus" ? 4 : 2, gift_advice: @gift_advice[name.downcase] }
      end
    end

    def build_gift_advice
      advisor = GiftAdvisor.new(@state)
      %w[caroline linus].to_h do |name|
        npc = friendship(name)
        due = !npc || (npc["gifts_today"].to_i == 0 && npc["gifts_this_week"].to_i < 2)
        [name, due ? advisor.recommend(name) : nil]
      end
    end

    def introduced?(name)
      npc = friendship(name)
      npc && (npc["talked_today"] == true || npc["points"].to_i > 0 || npc["introduced"] == true)
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
      cash_warning = @shopping && @shopping[:cash] < @shopping[:reserve] ? ["Day 2 Training Rod funding at risk: preserve at least #{@shopping[:reserve]}g tonight."] : []
      return cash_warning unless limit && @state["crops"].is_a?(Array)

      return cash_warning if @state["scarecrows"].is_a?(Array) && @state["scarecrows"].any? && @state["crops"].all? { |crop| @state["scarecrows"].any? { |scarecrow| (crop["x"].to_i - scarecrow["x"].to_i)**2 + (crop["y"].to_i - scarecrow["y"].to_i)**2 <= 49 } }

      count = @state["crops"].count { |crop| !crop["dead"] }
      cash_warning + ["Before scarecrow coverage is verified, keep total live outdoor crops at #{limit} or fewer (currently #{count})."]
    end
  end
end
