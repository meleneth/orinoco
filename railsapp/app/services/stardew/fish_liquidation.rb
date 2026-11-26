# frozen_string_literal: true

module Stardew
  class FishLiquidation
    # Vanilla sale prices. Unknown items are excluded, never treated as saleable.
    PRICES = {
      "129" => 75, "130" => 100, "131" => 40, "132" => 45,
      "136" => 100, "137" => 75, "138" => 75, "139" => 50,
      "140" => 25, "141" => 120, "142" => 30, "143" => 200,
      "144" => 75, "145" => 30, "146" => 100, "147" => 30,
      "148" => 85, "149" => 45, "150" => 100, "151" => 100,
      "152" => 20, "153" => 15, "154" => 200,
      "156" => 100, "157" => 200, "158" => 100, "159" => 50,
      "160" => 75, "161" => 150, "162" => 150, "163" => 150,
      "164" => 200, "165" => 200, "167" => 60, "267" => 60,
      "269" => 120, "698" => 75, "699" => 100, "700" => 75,
      "701" => 25, "702" => 150, "704" => 60, "705" => 25,
      "706" => 60, "707" => 75, "708" => 150, "709" => 55
    }.freeze
    STANDARD_BUNDLE = %w[128 130 131 132 136 140 142 143 144 145 148 150 156 164 698 699 700 701 706].freeze
    QUALITY = { 0 => 100, 1 => 125, 2 => 150, 4 => 200 }.freeze

    def initialize(state)
      @state = state
    end

    def call
      backpack = Array(@state["inventory"])
      stored = Array(@state["chests"]).flat_map { |chest| Array(chest["items"]) }
      reserves = STANDARD_BUNDLE.to_h { |id| [id, 1] }
      # Active bundle definitions add any remixed fish requirements conservatively.
      definitions = @state.dig("extras", "active_bundles")
      progress = @state.dig("extras", "bundle_progress")
      if definitions.is_a?(Hash)
        definitions.each do |key, definition|
          next unless definition.is_a?(String)
          fields = definition.split("/")
          next unless fields[2]
          slots = fields[2].split.each_slice(3).to_a
          slots.each_with_index do |(id, count, _quality), index|
            next unless PRICES.key?(id)
            flags = progress.is_a?(Hash) ? progress[key.split("/").last] : nil
            next if flags.is_a?(Array) && flags[index] == true

            reserves[id] = [reserves.fetch(id, 0), count.to_i].max
          end
        end
      end
      # Reserve from storage first, then lowest quality backpack stack.
      stored.each do |item|
        id = item["id"].to_s.delete_prefix("(O)")
        reserves[id] = [reserves.fetch(id, 0) - item["count"].to_i, 0].max
      end
      lines = backpack.sort_by { |item| item["quality"].to_i }.filter_map do |item|
        id = item["id"].to_s.delete_prefix("(O)")
        next unless PRICES.key?(id)

        count = item["count"].to_i
        next unless count.positive?

        price = PRICES.fetch(id) * QUALITY.fetch(item["quality"].to_i, 100) / 100
        professions = Array(@state["professions"])
        price = price * (professions.include?(8) ? 150 : professions.include?(6) ? 125 : 100) / 100
        keep = [count, reserves.fetch(id, 0)].min
        reserves[id] = reserves.fetch(id, 0) - keep
        { name: item["name"] || id, count: count, keep: keep, sell: count - keep,
          unit: price, gross: count * price, net: (count - keep) * price }
      end
      cash = @state["gold"].to_i
      net = lines.sum { |line| line[:net] }
      { cash: cash, gross: lines.sum { |line| line[:gross] }, net: net,
        liquid: cash + net, lines: lines, rod_shortfall: [1800 - cash - net, 0].max,
        bait_shortfall: [2000 - cash - net, 0].max }
    end
  end
end
