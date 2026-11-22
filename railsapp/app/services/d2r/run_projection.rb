# frozen_string_literal: true

require "json"
require "time"

module D2r
  # Redis-backed read model. All timestamps come from the event envelope so replay
  # and cross-game splits are deterministic; wall-clock rendering is a UI concern.
  class RunProjection
    KEY = "orinoco:d2r:run_projection:v1"
    HISTORY_LIMIT = 5

    def initialize(redis:)
      @redis = redis
    end

    def snapshot
      JSON.parse(@redis.get(KEY) || "{}").then { |stored| initial_state.merge(stored) }
    end

    def call(event)
      state = snapshot
      type = event.type
      payload = event.payload
      at = Time.iso8601(event.occurred_at).utc.iso8601(6)

      case type
      when "d2r.game.started"
        start_game(state, payload, at)
      when "d2r.game.ended"
        finish_step(state, at)
        state["game"]["ended_at"] = at if state["game"]
      when "d2r.run.selected"
        choose_run(state, payload, at)
      when "d2r.run.step"
        advance_step(state, payload, at)
      when "d2r.level.changed"
        state["level"] = Integer(payload.fetch("level"))
      when "d2r.area.changed"
        state["area"] = payload.fetch("area").to_s
      when "d2r.state.changed"
        state["screen"] = payload["current"] if payload["group"] == "screen"
      end

      if display_event?(type)
        state["events"].unshift({
          "type" => type, "at" => at, "message" => message(type, payload)
        })
        state["events"] = state["events"].first(HISTORY_LIMIT)
      end
      @redis.set(KEY, JSON.generate(state))
      state
    end

    private

    def initial_state
      { "game" => nil, "previous_run_kind" => nil, "run" => nil,
        "level" => nil, "area" => nil, "screen" => nil, "events" => [] }
    end

    def start_game(state, payload, at)
      finish_step(state, at)
      state["previous_run_kind"] = state.dig("run", "kind")
      state["game"] = { "id" => payload.fetch("game_id").to_s,
                        "started_at" => at, "ended_at" => nil }
      state["run"] = nil
      state["area"] = nil
      state["screen"] = nil
    end

    def choose_run(state, payload, at)
      raise ArgumentError, "game must be started before selecting a run" unless state["game"] && !state["game"]["ended_at"]

      kind = payload.fetch("kind").to_s.strip
      raise ArgumentError, "run kind cannot be blank" if kind.empty?

      finish_step(state, at)
      state["run"] = {
        "kind" => kind,
        "repeated" => state["previous_run_kind"] == kind,
        "started_at" => at,
        "step" => nil,
        "steps" => []
      }
    end

    def advance_step(state, payload, at)
      run = state["run"]
      raise ArgumentError, "run must be selected before its steps" unless run

      name = payload.fetch("name").to_s.strip
      raise ArgumentError, "step name cannot be blank" if name.empty?
      return if run.dig("step", "name") == name

      finish_step(state, at)
      run["step"] = { "name" => name, "started_at" => at }
    end

    def finish_step(state, at)
      run = state["run"]
      step = run && run["step"]
      return unless step

      elapsed = [Time.iso8601(at) - Time.iso8601(step.fetch("started_at")), 0].max
      run["steps"] << step.merge("ended_at" => at, "seconds" => elapsed.round(3))
      run["step"] = nil
    end

    def display_event?(type)
      !%w[d2r.state.changed].include?(type) && type.start_with?("d2r.")
    end

    def message(type, payload)
      case type
      when "d2r.game.started" then "Game started"
      when "d2r.game.ended" then "Game ended"
      when "d2r.run.selected" then "Run: #{'#{payload.fetch("kind")}'}"
      when "d2r.run.step" then "Step: #{'#{payload.fetch("name")}'}"
      when "d2r.level.changed" then "Level #{'#{payload.fetch("level")}'}"
      when "d2r.area.changed" then "Entered #{'#{payload.fetch("area")}'}"
      else
        type.delete_prefix("d2r.").tr(".", " ").capitalize
      end
    end
  end
end
