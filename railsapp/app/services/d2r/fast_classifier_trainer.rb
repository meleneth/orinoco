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

    def initialize(fingerprinter: FastFingerprint.new)
      @fingerprinter = fingerprinter
    end

    def train(truth_path:, fixture_root: File.dirname(truth_path))
      truth = YAML.safe_load_file(truth_path)
      groups = GROUP_ROIS.transform_values { |roi| { "roi" => roi, "max_distance" => 0.28, "templates" => {} } }

      truth.fetch("fixtures").select { |fixture| fixture.fetch("split") == "train" }.each do |fixture|
        fingerprints = @fingerprinter.call(File.join(fixture_root, fixture.fetch("file")))
        fixture.fetch("signals").each do |group, state|
          config = groups.fetch(group)
          templates = config.fetch("templates")
          templates[state] ||= []
          templates.fetch(state) << fingerprints.fetch(config.fetch("roi"))
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
