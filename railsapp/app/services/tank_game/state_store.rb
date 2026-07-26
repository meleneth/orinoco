# frozen_string_literal: true

require "json"

module TankGame
  class StateStore
    KEY = "tank_game:state"

    def initialize(redis:)
      @redis = redis
    end

    def read
      raw = @redis.get(KEY)
      return default_state if raw.nil? || raw.empty?

      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : default_state
    rescue JSON::ParserError
      default_state
    end

    def write!(state)
      @redis.set(KEY, JSON.generate(state))
      state
    end

    def clear!
      write!(default_state)
    end

    private

    def default_state
      {
        "phase" => "idle",
        "players" => [],
        "tanks" => [],
        "terrain" => [],
        "projectiles" => [],
        "explosions" => [],
        "status" => "Waiting for !TankGame",
        "winner" => nil
      }
    end
  end
end
