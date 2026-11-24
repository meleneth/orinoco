# frozen_string_literal: true

module VisualObserver
  module D2r
    module States
      ALL = %w[
        gameplay_idle area_banner waypoint_or_portal character_sheet skill_tree
        inventory_open item_tooltip_white item_tooltip_magic item_tooltip_rune
        stash_runes stash_other loading_screen character_select character_creation game_creation
        quest_log unrelated_screen boss_visible boss_dead death_screen
      ].freeze

      PROMPTS = {
        "gameplay_idle" => "Show ordinary gameplay with no panel or tooltip open.",
        "area_banner" => "Enter a new zone while its area title is visible.",
        "waypoint_or_portal" => "Open or approach the waypoint, map, or portal UI.",
        "character_sheet" => "Open the character screen with name, level, stats, and resistances visible.",
        "skill_tree" => "Open the current character's skill allocation panel.",
        "inventory_open" => "Open the inventory with the item grid visible and no tooltip.",
        "item_tooltip_white" => "Hover an unsocketed white item, ideally a Monarch.",
        "item_tooltip_magic" => "Hover a blue magic item, ideally Bramble Mitts.",
        "item_tooltip_rune" => "Hover a rune so its tooltip is visible.",
        "stash_runes" => "Open the rune stash tab with the full grid visible.",
        "stash_other" => "Open a non-rune stash tab.",
        "loading_screen" => "Prepare for the next natural loading transition.",
        "character_select" => "Return to the character selection roster. Capture the full roster UI, not the in-game character sheet.",
        "character_creation" => "Open the new-character creation screen with class selection and naming controls visible. Do not create a character just to capture this.",
        "game_creation" => "Open the Create Game screen with the selected character summary and difficulty controls visible.",
        "quest_log" => "Open the quest log on an act-ending quest page; use labels to record act, difficulty, and confirmed/incomplete truth.",
        "unrelated_screen" => "Show a non-D2R screen or an unrelated D2R menu that every gameplay recognizer must reject.",
        "boss_visible" => "Show Andariel or another target boss alive, if convenient.",
        "boss_dead" => "Show the boss aftermath or corpse, if it occurs naturally.",
        "death_screen" => "Show the death screen only if it occurred naturally."
      }.freeze

      PAIRS = {
        "area_banner" => [ %w[area_banner], %w[gameplay_idle] ],
        "transition_ui" => [ %w[waypoint_or_portal], %w[gameplay_idle] ],
        "character_panel" => [ %w[character_sheet skill_tree], %w[gameplay_idle] ],
        "inventory_panel" => [ %w[inventory_open stash_runes stash_other], %w[gameplay_idle] ],
        "item_tooltip" => [ %w[item_tooltip_white item_tooltip_magic item_tooltip_rune], %w[inventory_open gameplay_idle] ],
        "rune_stash" => [ %w[stash_runes], %w[stash_other] ],
        "loading_screen" => [ %w[loading_screen], %w[gameplay_idle] ],
        "character_select" => [ %w[character_select], %w[character_creation gameplay_idle] ],
        "character_creation" => [ %w[character_creation], %w[character_select gameplay_idle] ],
        "game_creation" => [ %w[game_creation], %w[character_select gameplay_idle] ],
        "quest_log" => [ %w[quest_log], %w[gameplay_idle character_sheet] ],
        "boss_state" => [ %w[boss_visible boss_dead], %w[gameplay_idle] ],
        "death_screen" => [ %w[death_screen], %w[gameplay_idle] ]
      }.freeze
    end
  end
end
