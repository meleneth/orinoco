# frozen_string_literal: true

run :year_one_community_center do
  title "Year One Community Center"
  starts spring(1)
  finishes winter(28)
  require_completion :community_center
  include_goals :introductions, :crops, :bundles, :fishing, :mining, :animals, :infrastructure, :relationships, :museum, :foraging, :artisan, :economy, :festivals, :exploration
  optimize :net_worth, weight: 30
  optimize :skill_progression, weight: 25
  optimize :friendship, weight: 20
  optimize :grandpa_evaluation, weight: 25
  constraints :preserve_bundle_items, :respect_energy_budget, :respect_travel_time, :respect_inventory_capacity, :avoid_unnecessary_passouts, :no_hidden_rng
end
