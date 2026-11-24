# frozen_string_literal: true

require "json"
require "time"

module D2r
  # Shared runtime presence state, independent of the user's master switch.
  # Only the screenshot processor writes observations; the capture worker reads.
  class ScanPresence
    KEY_PREFIX = "orinoco:d2r:observer:presence:"
    ACTIVE_STATES = %w[gameplay character_select character_creation loading_screen area_banner boss_visible boss_dead death_screen].freeze
    UNKNOWN_LIMIT = 6
    LEASE_SECONDS = 120

    def initialize(redis:, clock: -> { Time.now.utc })
      @redis = redis
      @clock = clock
    end

    def active?(source)
      read(source).fetch("active", false)
    end

    def observe(source, classification)
      previous = read(source)
      screen = classification.dig("signals", "screen", "state")
      recognized = ACTIVE_STATES.include?(screen)
      misses = recognized ? 0 : previous.fetch("misses", 0) + 1
      active = recognized || (previous.fetch("active", false) && misses < UNKNOWN_LIMIT)
      @redis.set(key(source), JSON.generate("active" => active, "misses" => misses,
        "screen" => screen, "observed_at" => @clock.call.iso8601(6)), ex: LEASE_SECONDS)
      active
    end

    private

    def key(source)
      "#{KEY_PREFIX}#{source}"
    end

    def read(source)
      raw = @redis.get(key(source))
      raw ? JSON.parse(raw) : {}
    rescue JSON::ParserError
      {}
    end
  end
end
