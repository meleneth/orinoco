# frozen_string_literal: true
require_relative "telemetry"

module Stardew
  class TelemetryProjection
    KEY = "orinoco:stardew:latest:v1"
    HISTORY_LIMIT = 256

    def initialize(redis:, clock: -> { Time.now.utc })
      @redis = redis
      @clock = clock
    end

    # Single consumer; duplicate or reordered messages cannot roll back state.
    def call(event)
      data = Telemetry.parse(JSON.generate(event.payload))
      key = "#{KEY}:#{data.fetch("save_id")}:#{data.fetch("player_id")}"
      previous = JSON.parse(@redis.get(key) || "{}")
      return if older?(data, previous)

      current = data.merge("received_at" => @clock.call.iso8601(6))
      encoded = JSON.generate(current)
      global = JSON.parse(@redis.get(KEY) || "{}")
      @redis.multi do |transaction|
        transaction.set(key, encoded)
        transaction.lpush("#{key}:history", encoded)
        transaction.ltrim("#{key}:history", 0, HISTORY_LIMIT - 1)
        transaction.set(KEY, encoded) unless older?(data, global)
      end
      current
    end

    def status
      data = JSON.parse(@redis.get(KEY) || "{}")
      age = data["received_at"] && [@clock.call - Time.iso8601(data["received_at"]), 0].max.round
      state = if age.nil?
        "waiting"
      elsif data["reason"] == "returned_to_title"
        "title"
      elsif age > 60
        "stale"
      else
        "connected"
      end
      { status: state, last_observation_seconds_ago: age, observation: data }
    end

    private

    def older?(data, previous)
      return false if previous.empty?
      return data["sequence"] <= previous["sequence"] if data["session_id"] == previous["session_id"]

      Time.iso8601(data.fetch("occurred_at")) <= Time.iso8601(previous.fetch("occurred_at"))
    end
  end
end
