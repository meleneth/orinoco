# frozen_string_literal: true

require "json"
require "time"
require "digest"
require_relative "run_inference"

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
        finish_area_step(state, at)
        finish_step(state, at)
        state["game"]["ended_at"] = at if state["game"]
      when "d2r.run.selected"
        choose_run(state, payload, at)
      when "d2r.run.step"
        advance_step(state, payload, at)
      when "d2r.character.selected", "d2r.character.created", "d2r.character.observed"
        observe_character(state, payload)
      when "d2r.level.changed"
        state["level"] = Integer(payload.fetch("level"))
      when "d2r.area.changed"
        state["area"] = payload.fetch("area").to_s
        track_area_step(state, at)
        D2r::RunInference.new.observe(state, event)
        sync_inferred_steps(state)
      when "d2r.difficulty.changed"
        state["difficulty"] = payload.fetch("difficulty").to_s
      when "d2r.terror_zones.changed"
        state["terror_zones"] = Array(payload.fetch("terror_zones")).map(&:to_s)
      when "d2r.state.changed"
        state["screen"] = payload["current"] if payload["group"] == "screen"
      when "d2r.loot.rune.sighted", "d2r.loot.unique.sighted"
        D2r::RunInference.new.observe(state, event)
        # The complete observation is archived; only the latest five events
        # remain in this ephemeral overlay read model.
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
      { "game" => nil, "previous_run_kind" => nil, "previous_run" => nil, "run" => nil,
        "visited_areas" => [], "area_steps" => [], "area_step" => nil,
        "level" => nil, "area" => nil, "difficulty" => nil, "terror_zones" => [],
        "screen" => nil, "events" => [] }
    end

    def start_game(state, payload, at)
      finish_area_step(state, at)
      finish_step(state, at)
      state["previous_run_kind"] = state.dig("run", "kind")
      state["previous_run"] = state["run"]
      state["game"] = { "id" => payload.fetch("game_id").to_s,
                        "started_at" => at, "ended_at" => nil }
      state["run"] = nil
      state["visited_areas"] = []
      state["area_steps"] = []
      state["area_step"] = nil
      state["area"] = nil
      state["difficulty"] = nil
      state["terror_zones"] = []
      state["screen"] = nil
    end

    def observe_character(state, payload)
      fields = %w[
        identity_key name character_class level experience experience_next_level
        unspent_attribute_points stats ladder hardcore expansion season observed_created_at
      ]
      previous = state["character"] || {}
      identity_key = payload["identity_key"]
      if identity_key.blank? && previous.slice("name", "character_class") == payload.slice("name", "character_class")
        identity_key = previous["identity_key"]
      end
      identity_key ||= fallback_identity_key(state, payload)
      state["character"] = previous.merge(payload.slice(*fields)).merge("identity_key" => identity_key)
      state["level"] = payload["level"] if payload["level"]
    end

    def fallback_identity_key(state, payload)
      seed = [ state.dig("game", "id"), payload["name"], payload["character_class"] ]
      "visual-session-#{Digest::SHA256.hexdigest(JSON.generate(seed)).first(24)}"
    end

    def track_area_step(state, at)
      return unless state["game"] && !state.dig("game", "ended_at")

      area = state["area"]
      return if area.nil? || state.dig("area_step", "name") == area

      finish_area_step(state, at)
      state["area_step"] = { "name" => area, "started_at" => at }
    end

    def finish_area_step(state, at)
      step = state["area_step"]
      return unless step

      state["area_steps"] ||= []
      state["area_steps"] << completed_step(step, at)
      state["area_step"] = nil
      sync_inferred_steps(state)
    end

    def sync_inferred_steps(state)
      run = state["run"]
      return unless run && run["inferred"]

      run["steps"] = Array(state["area_steps"]).dup
      run["step"] = state["area_step"]
    end

    def completed_step(step, at)
      elapsed = [ Time.iso8601(at) - Time.iso8601(step.fetch("started_at")), 0 ].max
      step.merge("ended_at" => at, "seconds" => elapsed.round(3))
    end

    def choose_run(state, payload, at)
      raise ArgumentError, "game must be started before selecting a run" unless state["game"] && !state["game"]["ended_at"]

      kind = payload.fetch("kind").to_s.strip
      raise ArgumentError, "run kind cannot be blank" if kind.empty?

      finish_step(state, at)
      state["run"] = {
        "kind" => kind,
        "repeated" => state["previous_run_kind"] == kind,
        "previous_steps" => state["previous_run_kind"] == kind ? Array(state.dig("previous_run", "steps")) : [],
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

      run["steps"] << completed_step(step, at)
      run["step"] = nil
    end

    def display_event?(type)
      !%w[
        d2r.state.changed d2r.loading.started d2r.loading.finished
        d2r.difficulty.changed d2r.terror_zones.changed
      ].include?(type) && type.start_with?("d2r.")
    end

    def message(type, payload)
      case type
      when "d2r.game.started" then "Game started"
      when "d2r.game.ended" then "Game ended"
      when "d2r.run.selected" then "Run: #{payload.fetch("kind")}"
      when "d2r.run.step" then "Step: #{payload.fetch("name")}"
      when "d2r.level.changed" then "Level #{payload.fetch("level")}"
      when "d2r.area.changed" then "Entered #{payload.fetch("area")}"
      when "d2r.loot.rune.sighted" then "Rune spotted: #{payload.fetch("name")}"
      when "d2r.loot.unique.sighted" then "Unique spotted: #{payload.fetch("name")}"
      else
        type.delete_prefix("d2r.").tr(".", " ").capitalize
      end
    end
  end
end
