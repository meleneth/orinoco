# frozen_string_literal: true

goal_set :introductions do
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
    target :harvest, :parsnip, quantity: 15
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
