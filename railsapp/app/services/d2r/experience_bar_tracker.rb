# frozen_string_literal: true

require "time"

module D2r
  class ExperienceBarTracker
    def initialize(max_gap_seconds: 3)
      @max_gap_seconds = max_gap_seconds
      @character = {}
      reset_sample
    end

    def reset_sample
      @previous = @previous_at = nil
    end

    # Returns true when an authoritative observation changes our known level.
    def seed(payload)
      return false unless payload["name"] && payload["character_class"]
      identity = payload.values_at("name", "character_class")
      switched = identity != @character.values_at("name", "character_class")
      if switched
        @character = {}
        reset_sample
      end
      old_level = @character["level"]
      @character.merge!(payload.slice("name", "character_class", "identity_key", "level").compact)
      changed = old_level != @character["level"]
      reset_sample if changed
      changed
    end

    def observe(fill, observed_at:)
      unless fill.is_a?(Numeric) && (0.0..1.0).cover?(fill)
        reset_sample
        return []
      end
      at = Time.iso8601(observed_at.to_s)
      previous = @previous
      gap = @previous_at && at - @previous_at
      @previous, @previous_at = fill, at
      level = @character["level"]
      return [] unless level.is_a?(Integer) && (1...99).cover?(level)
      return [] unless gap && gap.positive? && gap <= @max_gap_seconds
      return [] unless previous >= 0.90 && fill <= 0.10

      @character["level"] = level + 1
      [{ "type" => "d2r.level.changed", "payload" => @character.merge(
        "previous" => level, "source" => "xp_bar_rollover",
        "previous_fill" => previous, "fill" => fill
      ) }]
    end

    def level
      @character["level"]
    end
  end
end
