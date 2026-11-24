# frozen_string_literal: true

require "yaml"
require_relative "fast_fingerprint"

module D2r
  class FastClassifierTrainer
    GROUP_ROIS = {
      "screen" => "full",
      "left_panel" => "left_panel",
      "right_panel" => "right_panel",
      "tooltip" => "tooltip_zone"
    }.freeze
    SCREEN_MAX_DISTANCES = {
      "character_select" => 0.10,
      "character_creation" => 0.10,
      "game_creation" => 0.10,
      "loading_screen" => 0.05,
      "death_screen" => 0.07,
      "boss_dead" => 0.10,
      "area_banner" => 0.15,
      "boss_visible" => 0.18,
      "gameplay" => 0.22
    }.freeze

    def initialize(fingerprinter: FastFingerprint.new)
      @fingerprinter = fingerprinter
    end

    def train(truth_path:, fixture_root: File.dirname(truth_path))
      truth = YAML.safe_load_file(truth_path)
      groups = GROUP_ROIS.transform_values { |roi| { "roi" => roi, "max_distance" => 0.28, "templates" => {} } }
      groups.fetch("screen")["max_distances"] = SCREEN_MAX_DISTANCES
      groups.fetch("screen")["fallback"] = {
        "roi" => "game_hud", "state" => "gameplay", "max_distance" => 0.18, "templates" => []
      }

      truth.fetch("fixtures").select { |fixture| fixture.fetch("split") == "train" }.each do |fixture|
        fingerprints = @fingerprinter.call(File.join(fixture_root, fixture.fetch("file")))
        fixture.fetch("signals").each do |group, state|
          config = groups.fetch(group)
          templates = config.fetch("templates")
          templates[state] ||= []
          templates.fetch(state) << fingerprints.fetch(config.fetch("roi"))
        end
        if fixture.dig("signals", "screen") == "gameplay"
          fallback = groups.fetch("screen").fetch("fallback")
          fallback.fetch("templates") << fingerprints.fetch(fallback.fetch("roi"))
        end
      end

      {
        "version" => 1,
        "hash_columns" => FastFingerprint::HASH_COLUMNS,
        "hash_rows" => FastFingerprint::HASH_ROWS,
        "groups" => groups
      }
    end
  end
end
