# frozen_string_literal: true

require "json"

module Wos
  class OverlayStateStore
    KEY = "wos:overlay:latest"

    def initialize(redis:)
      @redis = redis
    end

    def read
      raw = @redis.get(KEY)
      return {} if raw.nil? || raw.empty?

      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def write!(state)
      payload = JSON.generate(state)
      @redis.set(KEY, payload)
      state
    end
  end
end