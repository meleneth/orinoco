# frozen_string_literal: true

goal_set :introductions do
  # Rendezvous estimates: Shoukry's GameFAQs walkthrough, Introductions Quest.
  # https://gamefaqs.gamespot.com/pc/701094-stardew-valley/faqs/74654?page=4
  [
    ["11:00", :marnies_ranch, %i[jas]],
    ["11:10", :leahs_cottage, %i[leah]],
    ["11:20", :willow_lane, %i[haley]],
    ["11:30", :jodis_house, %i[vincent jodi]],
    ["11:40", :town_square, %i[penny]],
    ["12:00", :alexs_house, %i[george evelyn]],
    ["12:10", :alexs_house_exterior, %i[alex]],
    ["12:10", :trailer, %i[pam]],
    ["12:20", :pierres_exterior, %i[sam]],
    ["12:30", :town_square, %i[marnie]],
    ["12:40", :pierres_store, %i[caroline abigail pierre]],
    ["12:50", :west_town_square, %i[harvey]],
    ["14:00", :emilys_house, %i[emily]],
    ["14:30", :saloon, %i[gus]],
    ["14:40", :joja_bridge, %i[maru]],
    ["15:10", :blacksmith, %i[clint]],
    ["15:20", :beach_bridge, %i[elliott]],
    ["16:00", :fish_shop_exterior, %i[lewis]],
    ["17:00", :jojamart, %i[shane]],
    ["18:40", :carpenters_shop, %i[sebastian]],
    ["18:50", :carpenters_exterior, %i[robin demetrius]],
    ["19:10", :linus_tent, %i[linus]]
  ].each_with_index do |(time, location, villagers), index|
    villagers.each do |npc|
      goal :"greet_#{npc}" do
        target :talk, npc, location: location, route_index: index,
          introduction: true, optional: %i[lewis robin].include?(npc)
        prefer_by spring(1), time: time
        priority :high
        strategy :respect_npc_schedule
      end
    end
  end

  goal :greet_willy do
    target :talk, :willy, location: :beach, introduction: true
    prefer_by spring(2)
    priority :high
    strategy :respect_npc_schedule
  end

  goal :meet_villagers do
    target :talk, :introductions, selector: :quest_targets, quantifier: :all
    prefer_by spring(1)
    deadline spring(3)
    priority :high
    strategy :cluster_by_location
    strategy :respect_npc_schedule
  end
  goal :first_gift do
    target :complete, :how_to_win_friends
    requires :meet_villagers
    prefer_by spring(4)
  end
end

goal_set :crops do
  goal :first_parsnip_harvest do
    target :harvest, :parsnip, quantity: 13
    prefer_by spring(5)
  end
  %i[spring summer fall].each do |season|
    goal :"#{season}_crops" do
      target :reserve, :"#{season}_crops", selector: :active_bundle
      deadline public_send(season, 28)
      strategy :calculate_seed_requirements
    end
  end
  goal :quality_crops do
    target :complete, :quality_crops, selector: :active_bundle
    strategy :account_for_quality_probability
    strategy :optimize_fertilizer
  end
  recurring :crop_maintenance do
    target :maintain, :required_crops
    every :day
    strategy :water_and_harvest
  end
end

goal_set :bundles do
  goal :community_center do
    target :complete, :community_center, selector: :active_bundles
    deadline winter(28)
    priority :critical
    strategy :expand_bundle_dependencies
  end
  goal :red_cabbage do
    target :acquire, :red_cabbage
    when_needed :red_cabbage
    deadline winter(28)
    priority :critical
    route :purchase, item: :red_cabbage, source: :traveling_cart
    route :grow, seed: :red_cabbage_seeds
  end
  recurring :cart_visit do
    target :maintain, :traveling_cart_check
    every :friday, :sunday
    when_needed :red_cabbage
    priority :critical
  end
end

goal_set :fishing do
  goal :fishing_rod do
    target :acquire, :fishing_rod
    prefer_by spring(2)
  end
  goal :fish_bundles do
    target :complete, :fish_tank, selector: :active_bundles
    strategy :prioritize_weather_windows
    strategy :reserve_fishing_time
  end
end

goal_set :mining do
  goal :mine_access do
    target :unlock, :mines
    prefer_by spring(5)
  end
  [40, 80, 120].each do |floor|
    goal :"mine_floor_#{floor}" do
      target :reach, :mine_floor, quantity: floor
      requires(floor == 40 ? :mine_access : :"mine_floor_#{floor - 40}")
    end
  end
end

goal_set :animals do
  goal :animal_products do
    target :reserve, :animal_products, selector: :active_bundles
    strategy :backchain_buildings_and_maturity
  end
end

goal_set :infrastructure do
  goal :greenhouse do
    target :unlock, :greenhouse
    strategy :expand_bundle_dependencies
  end
  goal :sprinklers do
    target :build, :sprinkler_coverage
    strategy :optimize_labor_savings
  end
end

goal_set :relationships do
  recurring :birthday_gifts do
    target :gift, :birthday_villagers, selector: :calendar
    every :day
    strategy :respect_npc_schedule
  end
end

goal_set :museum do
  goal :museum_progress do
    target :deliver, :museum_donations, quantity: 60
    prefer_by winter(28)
  end
end

goal_set :foraging do
  goal :forage_bundles do
    target :complete, :crafts_room, selector: :active_bundles
    strategy :prioritize_seasonal_windows
  end
end

goal_set :artisan do
  goal :artisan_products do
    target :reserve, :artisan_products, selector: :active_bundles
    strategy :backchain_processing
  end
end

goal_set :economy do
  goal :vault do
    target :complete, :vault, selector: :active_bundles
    strategy :reserve_required_expenses
  end
end

goal_set :festivals do
  goal :strawberry_investment do
    target :acquire, :strawberry_seeds, opportunity: :egg_festival
    prefer_by spring(13)
    strategy :maximize_remaining_harvest_value
  end
end

goal_set :exploration do
  goal :community_center_access do
    target :unlock, :community_center
    prefer_by spring(5)
  end
  goal :wizard_access do
    target :unlock, :wizard_bundle_translation
    requires :community_center_access
    prefer_by spring(6)
  end
end
