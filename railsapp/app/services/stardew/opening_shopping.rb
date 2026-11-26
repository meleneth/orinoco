# frozen_string_literal: true

module Stardew
  class OpeningShopping
    SEEDS = [
      { name: "Parsnip Seeds", id: "472", harvest: "24", target: 13, price: 20 },
      { name: "Bean Starter", id: "473", harvest: "188", target: 1, price: 60 },
      { name: "Cauliflower Seeds", id: "474", harvest: "190", target: 1, price: 80 }
    ].freeze
    KALE_PRICE = 70

    def initialize(state)
      @state = state
    end

    def call
      return unless @state.values_at("year", "season", "day") == [1, "spring", 1]
      return unless @state["gold"].is_a?(Integer) && @state["inventory"].is_a?(Array) && @state["crops"].is_a?(Array)

      cash = @state["gold"]
      required = SEEDS.filter_map do |seed|
        planted = @state["crops"].count { |crop| !crop["dead"] && crop["harvest_id"].to_s.delete_prefix("(O)") == seed[:harvest] }
        missing = [seed[:target] - planted - owned(seed[:id]), 0].max
        seed.merge(quantity: missing, cost: missing * seed[:price]) if missing.positive?
      end
      required_cost = required.sum { |seed| seed[:cost] }
      kale = [cash - required_cost, 0].max / KALE_PRICE
      purchases = required.dup
      purchases << { name: "Kale Seeds", quantity: kale, price: KALE_PRICE, cost: kale * KALE_PRICE } if kale.positive?
      { purchases: purchases, required_cost: required_cost, affordable: cash >= required_cost,
        total: purchases.sum { |seed| seed[:cost] }, cash: cash,
        kale_owned: owned("477"), at_shop: @state["location"] == "SeedShop",
        complete: purchases.empty? && cash >= required_cost }
    end

    private

    def owned(id)
      items = @state["inventory"] + Array(@state["chests"]).flat_map { |chest| Array(chest["items"]) }
      items.sum { |item| item["id"].to_s.delete_prefix("(O)") == id ? item["count"].to_i : 0 }
    end
  end
end
