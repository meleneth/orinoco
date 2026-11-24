# frozen_string_literal: true

require "yaml"
require_relative "fast_fingerprint"

module D2r
  class FastClassifier
    Classification = Data.define(:signals, :elapsed_ms) do
      def to_h
        { "signals" => signals, "elapsed_ms" => elapsed_ms }
      end
    end

    def initialize(model_path: default_model_path, fingerprinter: FastFingerprint.new, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @model = YAML.safe_load_file(model_path)
      @fingerprinter = fingerprinter
      @clock = clock
    end

    def call(path)
      started_at = @clock.call
      fingerprints = @fingerprinter.call(path)
      signals = @model.fetch("groups").to_h do |group, config|
        result = classify_group(fingerprints.fetch(config.fetch("roi")), config)
        result = classify_fallback(fingerprints, config.fetch("fallback")) if result.fetch("state") == "unknown" && config["fallback"]
        [ group, result ]
      end
      Classification.new(signals:, elapsed_ms: ((@clock.call - started_at) * 1_000).round(3))
    end

    private

    def classify_group(actual, config)
      candidates = config.fetch("templates").map do |state, templates|
        distance = templates.map { |template| @fingerprinter.distance(actual, template) }.min
        { "state" => state, "distance" => distance.round(4) }
      end.sort_by { |candidate| candidate.fetch("distance") }
      best = candidates.first
      second = candidates.fetch(1, best)
      max_distance = config.fetch("max_distances", {}).fetch(best.fetch("state"), config.fetch("max_distance"))
      state = best.fetch("distance") <= max_distance ? best.fetch("state") : "unknown"
      margin = second.fetch("distance") - best.fetch("distance")
      confidence = ((1.0 - best.fetch("distance")) * 0.8) + ([ margin, 0.0 ].max * 0.2)
      best.merge("state" => state, "confidence" => confidence.clamp(0.0, 1.0).round(4), "margin" => margin.round(4))
    end

    def classify_fallback(fingerprints, config)
      actual = fingerprints.fetch(config.fetch("roi"))
      distance = config.fetch("templates").map { |template| @fingerprinter.distance(actual, template) }.min
      state = distance && distance <= config.fetch("max_distance") ? config.fetch("state") : "unknown"
      confidence = distance ? (1.0 - distance).clamp(0.0, 1.0).round(4) : 0.0
      { "state" => state, "distance" => distance&.round(4), "confidence" => confidence, "margin" => 0.0,
        "fallback" => config.fetch("roi") }
    end

    def default_model_path
      return Rails.root.join("config", "d2r_fast_classifier.yml") if defined?(Rails)

      File.expand_path("../../../config/d2r_fast_classifier.yml", __dir__)
    end
  end
end
