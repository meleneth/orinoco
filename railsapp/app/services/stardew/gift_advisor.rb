# frozen_string_literal: true

module Stardew
  class GiftAdvisor
    # Explicit conservative subset of verified gifts, not a universal taste table.
    # https://stardewvalleywiki.com/Linus
    # https://stardewvalleywiki.com/Caroline
    ITEMS = {
      "399" => ["Spring onion", 0], "18" => ["Daffodil", 1],
      "20" => ["Leek", 1], "22" => ["Dandelion", 1],
      "16" => ["Wild horseradish", 1], "296" => ["Salmonberry", 0],
      "396" => ["Spice berry", 1], "398" => ["Grape", 1],
      "406" => ["Wild plum", 1], "408" => ["Hazelnut", 1],
      "412" => ["Winter root", 1], "416" => ["Snow yam", 1],
      "414" => ["Crystal fruit", 1], "404" => ["Common mushroom", 1],
      "280" => ["Yam", 1], "88" => ["Coconut", 1], "90" => ["Cactus fruit", 1],
      "614" => ["Green tea", 0], "593" => ["Summer spangle", 0],
      "815" => ["Tea leaves", 0], "233" => ["Ice cream", 0]
    }.freeze
    TASTES = {
      "linus" => { loved: %w[280 88 90], liked: %w[399 18 20 22 16 296 396 398 406 408 412 416 414 404] },
      "caroline" => { loved: %w[614 593], liked: %w[18 16 815] }
    }.freeze
    FALLBACK = {
      "spring" => { "linus" => "Forage a spring onion in southern Cindersap Forest, or a spare leek or daffodil.",
                    "caroline" => "Forage a spare daffodil or wild horseradish along town or forest paths." },
      "summer" => { "linus" => "Forage a spare spice berry or grape.", "caroline" => "Grow a Summer Spangle from Pierre's seeds." },
      "fall" => { "linus" => "Forage a spare hazelnut or wild plum.", "caroline" => "Harvest tea leaves during the final week if a tea bush is available; otherwise retrieve a stored daffodil." },
      "winter" => { "linus" => "Dig up a spare winter root or snow yam.", "caroline" => "Retrieve a stored daffodil or brew green tea if available." }
    }.freeze

    def initialize(state)
      @state = state
      @remaining = Array(state["inventory"]).group_by { |item| item["id"].to_s.delete_prefix("(O)") }
                        .transform_values { |items| items.sum { |item| item["count"].to_i } }
    end

    def recommend(name, allocate: true)
      name = name.downcase
      tastes = TASTES.fetch(name)
      options = Array(@state["inventory"]).filter_map do |item|
        id = item["id"].to_s.delete_prefix("(O)")
        next unless ITEMS.key?(id)
        taste = tastes[:loved].include?(id) ? :loved : (tastes[:liked].include?(id) ? :liked : nil)
        next unless taste
        label, reserve = ITEMS.fetch(id)
        next unless @remaining.fetch(id, 0) > reserve && item["count"].to_i.positive?
        quality = item["quality"].to_i
        multiplier = { 0 => 100, 1 => 110, 2 => 125, 4 => 150 }.fetch(quality, 100)
        { id: id, label: label, taste: taste, quality: quality, score: (taste == :loved ? 80 : 45) * multiplier }
      end
      best = options.max_by { |item| [item[:score], -ITEMS.fetch(item[:id]).last, item[:id]] }
      if best
        @remaining[best[:id]] -= 1 if allocate
        quality = { 1 => "silver", 2 => "gold", 4 => "iridium" }[best[:quality]]
        return { available: true, text: "Gift #{best[:label]}#{quality ? " (#{quality} quality)" : ""} (#{best[:taste]})." }
      end
      { available: false, text: FALLBACK.fetch(@state["season"], FALLBACK["spring"]).fetch(name) }
    end
  end
end
