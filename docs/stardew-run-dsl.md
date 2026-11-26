# Stardew run declaration DSL

Status: proposed language contract; compiler/runtime not implemented. Companion to [Year-One Coach](stardew-year-one-coach.md).

## Boundaries

Four independent layers: observed save state, versioned game rules/action catalog, declarative run goals, deterministic planner. Ruby DSL is trusted repository source only, never arbitrary user-submitted Ruby or save-supplied code. Compile to immutable, serializable IR; evaluate plans against IR, not Ruby blocks. No network, clock, randomness, game API, Rails models or mutation in declarations. Compiler validates references, units, cycles, dates, capabilities and objective weights. Game version and ruleset revision are explicit.

Suggested layout:
- railsapp/config/stardew/runs/year_one_community_center.rb
- railsapp/config/stardew/goals/{introductions,crops,fishing,mining,animals,friendship,museum,infrastructure,bundles}.rb
- railsapp/app/services/stardew/{dsl,planning,rules}/
- railsapp/spec/services/stardew/{dsl,planning}/

## Example (illustrative syntax, not executable yet)

```ruby
run :year_one_community_center do
  title "Year One Community Center"
  starts spring(1)
  finishes winter(28)
  require_completion :community_center

  include_goals :introductions
  include_goals :seasonal_bundles
  include_goals :crop_progression
  include_goals :fishing_progression
  include_goals :mine_progression
  include_goals :animal_husbandry
  include_goals :farm_infrastructure
  include_goals :villager_friendships
  include_goals :museum_collection

  optimize :net_worth, weight: 30
  optimize :skill_progression, weight: 25
  optimize :friendship, weight: 20
  optimize :grandpa_evaluation, weight: 25

  constraints do
    preserve_bundle_items
    respect_energy_budget
    respect_travel_time
    respect_inventory_capacity
    avoid_unnecessary_passouts
    no_hidden_rng
  end
end

goal_set :introductions do
  goal :meet_villagers do
    target villagers(required_for: :introductions)
    prefer_by spring(1)
    deadline spring(3)
    completion :introduced_to_each
    strategy :cluster_by_location
    strategy :respect_npc_schedule
    strategy :minimize_travel
    priority :high
  end

  goal :give_first_gift do
    requires :meet_villagers
    completion quest_completed("How to Win Friends")
    prefer_by spring(4)
  end
end

goal_set :crop_progression do
  goal :first_parsnip_harvest do
    harvest :parsnip, quantity: 15
    prefer_by spring(5)
  end

  goal :spring_bundle_crops do
    reserve_items_for_bundle :spring_crops
    deadline spring(28)
  end

  goal :quality_crops do
    satisfy_bundle :quality_crops
    strategy :optimize_fertilizer
    strategy :calculate_seed_requirements
    strategy :account_for_quality_probability
  end

  goal :strawberry_investment do
    opportunity festival(:egg_festival)
    invest_available_gold_in :strawberry_seeds,
      reserve: :upcoming_required_expenses
    strategy :maximize_remaining_harvest_value
  end

  recurring :crop_maintenance do
    every :day
    ensure_watered :all_required_crops
    harvest_when_ready
  end
end

goal_set :seasonal_bundles do
  goal :red_cabbage do
    acquire :red_cabbage, quantity: 1
    deadline winter(28)
    acquisition_routes do
      purchase :red_cabbage, from: :traveling_cart
      grow :red_cabbage, from: :red_cabbage_seeds
    end
    priority :critical
  end

  recurring :traveling_cart_visit do
    every :friday, :sunday
    while_needed :red_cabbage
    action :inspect_traveling_cart
    priority :critical
  end

  goal :rain_fish do
    satisfy_bundle :river_fish
    strategy :prioritize_weather_windows
    strategy :reserve_fishing_time
  end
end
```

Examples are intent, not verified optimal play. Dates other than campaign completion are tunable milestones; missed milestones must not invalidate the entire run. Fifteen parsnips assumes standard starting conditions. Actual bundle data controls whether red cabbage and other bundle goals are activated. Rain fishing strategy applies to relevant fish only; do not assume all river fish require rain. Traveling Cart additional valid opportunities come from game rules.

## Semantics

- Hard requirements are lexicographically ahead of normalized secondary score; infeasible hard requirements produce explanations and best-effort recovery, never fabricated plans. Deadline can be missed and remains visible; distinguish campaign requirements from local targets. prefer_by is a soft preference.
- Goal types: acquire, reserve, deliver, harvest cumulative, plant, reach skill/level, unlock, talk to each, gift, complete quest/bundle, build, earn, maintain. Explicit distinction between cumulative harvest, current inventory and delivered quantities.
- Quantification: all/any/n-of selectors, dynamic expansion from observed bundles or registry, alternative acquisition routes, quantity and minimum quality, recurrence and conditional activation, prerequisites and ordered milestones.
- Stable goal IDs and recurrence instance keys (save/player/day as appropriate). Goal state: unknown, pending, actionable, in_progress, satisfied, at_risk, blocked, missed, not_applicable. Completion comes from authoritative observations; no manual checkoff masquerading as fact.
- Resource reservations are allocation records, not independent per-goal counts. A single item cannot be allocated to incompatible consumptive goals. Bundle alternatives are choice groups; planner may choose cheapest feasible alternative and revise before delivery. Use qualified item IDs, not localized names.
- Availability and duration live in action catalog: planting/harvesting, shop purchases, travel, NPC conversations, fishing, tool upgrades, crafting, construction, etc. Catalog describes preconditions, effects, stochastic outcomes, time, energy, gold, slots and valid windows. No hidden RNG in default fair-play mode.
- Backward chain from required outcome to feasible actions; forward simulate candidate schedules. Distinguish expected outcomes, guaranteed outcomes and uncertainty. Rank actions by slack, dependency criticality, marginal score and opportunity cost. Return today schedule and horizon risks with explanation and source goal ID.
- Score normalization and caps must be explicit and versioned so raw gold cannot swamp skill/friendship metrics. Default weights illustrative; use a separate Grandpa score metric derived from documented game evaluation rules, not an invented game score. Score and campaign profile revisions stored with replay.

## Compiler and planner milestones

1. Define typed IR and Ruby builder with explicit methods; reject unknown directives, duplicate IDs, unresolved refs and dependency cycles. Canonical JSON export and digest; deterministic golden tests.
2. Compile default profile and reusable goal sets. Implement conditional selectors from actual bundle data; fixture coverage across all four seasons and remixed bundles. Add declarative coverage audit listing unmodeled requirements/actions, never silently ignore them.
3. Implement action catalog and bounded deterministic planner, starting with introductions, crops and bundle reserves. Validate weather windows, shop hours, travel, energy, crop growth and risk. Explain blocked goals and offer recovery.
4. Extend through fishing, mining, animals, buildings, friendship, museum, cart and festivals. Full 112-day replay fixture; compare scores against baseline, document coverage and unknowns.
5. Feed compiled profile revision and planner outputs into existing SNS/SQS affordance, PostgreSQL archive and Redis/Hotwire projection. Test replan on observed change, dedupe, stale data, rewind/day restart, missed deadline and switching profiles.

## Required tests

- Spring 1 accessible NPCs and Spring 2 unavailable-first-day target; no impossible route.
- Growth dates including season transitions, regrowth, greenhouse, fertilizer and watering delays.
- Bundle alternatives, exact quantity/quality reservation, shared inventory, no double counting.
- Red cabbage acquired as crop versus seed; uncertain cart stock; late greenhouse dependency; remixed bundle not requiring it.
- Rain-only fish opportunity and missed window; planner does not prescribe inaccessible location.
- Gold reserve for future infrastructure versus seasonal purchases; bounded energy/time; deterministic tie breaks.
- Day-one missed objective rolls forward, hard deadline missed emits risk/recovery, replay identical at same snapshot/ruleset/profile.
- DSL source is declarative, no per-goal arbitrary planner callbacks; reusable strategies are separately tested.
