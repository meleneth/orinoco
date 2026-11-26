# frozen_string_literal: true
require_relative "telemetry"
require_relative "daily_agenda"

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

      # Only latch historical achievements, never current resource balances or daily chores.
      # A new session may be a rollback to the beginning of an unsaved day.
      # Commit achievements at the game's save boundary; discard provisional evidence
      # when a new session loads the same or an earlier day.
      ledger_key = "#{key}:milestones:v1"
      ledger = JSON.parse(@redis.get(ledger_key) || "{}")
      if data["state"]
        state = data.fetch("state")
        day = [state["year"], DailyAgenda::SEASONS.index(state["season"]), state["day"]]
        committed = Array(ledger["committed"]).select { |entry| (entry["day"] <=> day) <= 0 }
        provisional = ledger["session"] == data["session_id"] ? Array(ledger["provisional"]) : []
        state["completed_milestones"] = (committed + provisional).map { |entry| entry["id"] }.uniq
        profile = DailyAgenda.profile
        agenda = DailyAgenda.new(profile: profile, state: state).call
        latchable = %w[first_chest_wood initial_planting second_planting first_parsnip_harvest
                       fishing_rod fiberglass_rod copper_pickaxe beach_bridge gatherer
                       caroline_sunroom tea_sapling_recipe meet_villagers first_gift]
        agenda[:tasks].each do |task|
          next unless task[:status] == "complete"
          next unless latchable.include?(task[:id]) || task[:target].dig("options", "introduction")
          next if state["completed_milestones"].include?(task[:id])

          provisional << { "id" => task[:id], "day" => day }
          state["completed_milestones"] << task[:id]
        end
        if data["reason"] == "saved"
          committed = (committed + provisional).uniq { |entry| entry["id"] }
          provisional = []
        end
        ledger = { "session" => data["session_id"], "committed" => committed, "provisional" => provisional }
      end
      current = data.merge("received_at" => @clock.call.iso8601(6))
      encoded = JSON.generate(current)
      global = JSON.parse(@redis.get(KEY) || "{}")
      @redis.multi do |transaction|
        transaction.set(key, encoded)
        transaction.set(ledger_key, JSON.generate(ledger)) if data["state"]
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
