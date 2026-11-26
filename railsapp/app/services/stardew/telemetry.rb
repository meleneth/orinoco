# frozen_string_literal: true
require "json"
require "time"

module Stardew
  module Telemetry
    class Invalid < ArgumentError; end
    MAX_BYTES = 200_000
    REASONS = %w[save_loaded day_started day_ending saved returned_to_title snapshot manual warped inventory_changed].freeze

    def self.parse(raw)
      raise Invalid, "snapshot too large" if raw.bytesize > MAX_BYTES

      data = JSON.parse(raw)
      raise Invalid, "expected object" unless data.is_a?(Hash)
      raise Invalid, "unsupported schema" unless data["schema_version"] == 1
      %w[event_id session_id save_id player_id].each do |key|
        size = %w[save_id player_id].include?(key) ? 64 : 32
        raise Invalid, "invalid #{key}" unless data[key].is_a?(String) && data[key].size == size && /\A[0-9a-f]+\z/.match?(data[key])
      end
      raise Invalid, "invalid sequence" unless data["sequence"].is_a?(Integer) && data["sequence"].positive?
      raise Invalid, "invalid reason" unless REASONS.include?(data["reason"])

      Time.iso8601(data.fetch("occurred_at"))
      state = data["state"]
      if data["reason"] == "returned_to_title"
        raise Invalid, "unexpected title state" unless state.nil?
      else
        raise Invalid, "missing state" unless state.is_a?(Hash)
        raise Invalid, "invalid season" unless %w[spring summer fall winter].include?(state["season"])
        raise Invalid, "invalid day" unless state["day"].is_a?(Integer) && (1..28).cover?(state["day"])
        raise Invalid, "invalid year" unless state["year"].is_a?(Integer) && state["year"].positive?
      end
      data
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError => e
      raise Invalid, e.message
    end
  end
end
