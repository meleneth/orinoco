# frozen_string_literal: true

# The 2020 devblog guide, revised by the Jan/Feb 2026 planning discussions.
# Milestones are preferences unless the game actually imposes a deadline.
goal_set :opening_strategy do
  goal :initial_planting do
    target :plant, :opening_plot, quantity: 15,
      crops: { parsnip: 13, green_bean: 1, cauliflower: 1 },
      rows: 3, columns: 5
    deadline spring(1)
    priority :high
    strategy :respect_crow_limit
  end

  goal :jas_introduction do
    target :talk, :jas, location: :marnies_ranch
    prefer_by spring(1), time: "11:00"
    strategy :respect_npc_schedule
  end

  goal :opening_wood do
    target :acquire, :wood, quantity: 100
    prefer_by spring(1)
    strategy :top_trees
  end

  goal :opening_kale_seeds do
    target :acquire, :kale_seeds, budget: :remaining_after_required_seeds
    prefer_by spring(1)
    strategy :reserve_for_scarecrow
  end

  goal :foraging_one do
    target :reach, :foraging_skill, quantity: 1
    prefer_by spring(1)
  end

  goal :farming_one do
    target :reach, :farming_skill, quantity: 1
    prefer_by spring(5)
  end

  goal :reserve_parsnips do
    target :reserve, :parsnip, quantity: 2
    prefer_by spring(5)
  end

  goal :second_planting do
    target :plant, :second_plot, quantity: 13,
      crops: { potato: 1, kale: 12 }, fertilizer: :none
    prefer_by spring(5)
    strategy :respect_crow_limit
  end

  goal :scarecrow do
    target :build, :scarecrow
    requires :farming_one
    prefer_by spring(6)
    priority :high
  end

  goal :expand_kale do
    target :plant, :kale, quantity_policy: :available_seeds_and_protected_capacity
    requires :scarecrow
    prefer_by spring(6)
    strategy :respect_crow_limit
  end

  { house: 1, ocean_fishing: 2, mountain_fishing: 2, mines: 5 }.each do |location, day|
    goal :"chest_#{location}" do
      target :build, :chest, location: location
      prefer_by spring(day)
      strategy :safe_chest_placement
    end
  end

  { 2 => 2, 3 => 3, 4 => 4, 7 => 10 }.each do |level, day|
    goal :"fishing_level_#{level}" do
      target :reach, :fishing_skill, quantity: level
      prefer_by spring(day)
      strategy :prioritize_fishing_income
    end
  end

  goal :beach_bridge do
    target :unlock, :beach_bridge
    prefer_by spring(3)
  end

  goal :fiberglass_rod do
    target :acquire, :fiberglass_rod
    requires :fishing_level_2
    prefer_by spring(3)
    strategy :reserve_bundle_items
  end

  goal :strawberry_cash do
    target :reserve, :gold, quantity: 4000, purpose: :strawberry_seeds
    prefer_by spring(13), time: "09:00"
    priority :high
  end

  goal :farming_two do
    target :reach, :farming_skill, quantity: 2
    prefer_by spring(13)
  end

  goal :strawberry_planting do
    target :plant, :strawberry, quantity: 40, quantity_policy: :maximize_feasible
    prefer_by spring(13)
    strategy :maximize_remaining_harvest_value
  end

  goal :foraging_five do
    target :reach, :foraging_skill, quantity: 5
    prefer_by spring(14)
    priority :high
  end

  goal :gatherer do
    target :unlock, :gatherer_profession
    requires :foraging_five
    prefer_by spring(15)
    priority :high
  end

  recurring :salmonberries do
    target :harvest, :salmonberry, quantity_policy: :maximize_feasible
    every :day
    window spring(15), spring(18)
    priority :high
    strategy :reserve_energy_food
  end

  goal :copper_pickaxe do
    target :acquire, :copper_pickaxe
    prefer_by spring(10)
    strategy :schedule_tool_downtime
  end

  goal :minecarts do
    target :unlock, :minecarts
    strategy :expand_bundle_dependencies
    priority :high
  end

  recurring :spring_seeds do
    target :plant, :spring_seeds, quantity_policy: :surplus_after_bundle_reserves
    every :day
    window spring(1), spring(10)
    strategy :respect_crow_limit
  end
end

goal_set :daily_routine do
  recurring :pet_care do
    target :maintain, :pet_friendship
    every :day
  end

  recurring :inventory_sort do
    target :maintain, :inventory_space
    every :day
  end

  recurring :spring_onion_check do
    target :maintain, :spring_onion_patch_check, location: :cindersap_forest
    every :day
    window spring(1), spring(28)
    priority :high
    strategy :first_morning_outing
  end

  recurring :spring_onions do
    target :harvest, :spring_onion, quantity_policy: :maximize_feasible
    every :day
    window spring(1), spring(28)
    priority :high
    strategy :first_morning_outing
    strategy :reserve_energy_food
  end

  recurring :forage_sweep do
    target :acquire, :seasonal_forage, quantity_policy: :maximize_feasible
    every :saturday
  end

  recurring :cooking_tv do
    target :maintain, :queen_of_sauce_recipes
    every :sunday
  end

  recurring :caroline_conversation do
    target :talk, :caroline
    every :day
    when_needed :caroline_two_hearts
    strategy :respect_npc_schedule
  end

  goal :caroline_two_hearts do
    target :reach, :caroline_friendship, quantity: 2, unit: :hearts
    strategy :optimize_gifts
    priority :high
  end

  goal :caroline_sunroom do
    target :complete, :caroline_sunroom_event
    requires :caroline_two_hearts
    strategy :respect_npc_schedule
  end

  goal :tea_sapling_recipe do
    target :unlock, :tea_sapling_recipe
    requires :caroline_sunroom
  end

  recurring :tea_sapling_income do
    target :earn, :tea_sapling_profit, quantity_policy: :positive_margin
    every :day
    requires :tea_sapling_recipe
    strategy :reserve_bundle_items
  end

  recurring :watering_can_upgrade do
    target :maintain, :watering_can_upgrade_opportunity
    every :day
    strategy :schedule_around_rain
    strategy :avoid_strawberry_disruption
  end

  recurring :lucky_mining do
    target :reach, :mine_progress, quantity_policy: :maximize_feasible
    every :day
    strategy :prefer_high_daily_luck
  end

  recurring :cart_investments do
    target :acquire, :traveling_cart_investments,
      repeat_items: %i[iridium_ore iridium_bar ancient_seed],
      once_items: %i[rare_seed coffee_bean void_egg],
      quantity_policy: :affordable_after_required_expenses
    every :friday, :sunday
    strategy :reserve_required_expenses
  end
end

goal_set :compounding_production do
  goal :oak_resin do
    target :acquire, :oak_resin, quantity_policy: :support_keg_capacity
    strategy :backchain_processing
  end

  goal :fruit_orchard do
    target :plant, :fruit_trees, location: :greenhouse
    requires :greenhouse
    strategy :maximize_remaining_harvest_value
  end

  goal :keg_capacity do
    target :build, :keg, quantity_policy: :maximize_profitable_capacity
    strategy :backchain_processing
  end

  goal :rhubarb_processing do
    target :maintain, :rhubarb_processing, quantity: 10
    prefer_by spring(20)
    strategy :validate_access_and_growth
    strategy :maximize_summer_investment
  end

  goal :starfruit_production do
    target :plant, :starfruit, quantity: 380, quantity_policy: :maximize_feasible
    prefer_by summer(1)
    strategy :validate_access_and_growth
    strategy :reserve_required_expenses
  end

  goal :expanded_keg_capacity do
    target :build, :keg, quantity: 60
    prefer_by winter(28)
    strategy :backchain_processing
  end

  goal :island_pineapples do
    target :plant, :pineapple, location: :ginger_island, quantity_policy: :maximize_feasible
    requires :community_center
    strategy :validate_access_and_growth
  end
end
