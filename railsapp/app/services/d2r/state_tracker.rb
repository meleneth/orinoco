# frozen_string_literal: true

require "time"

module D2r
  class StateTracker
    IMMEDIATE_SCREEN_STATES = %w[loading_screen].freeze
    HIGH_RISK_SCREEN_STATES = %w[boss_visible boss_dead death_screen].freeze
    DOMAIN_EVENTS = {
      "area_banner" => "d2r.area.banner.visible",
      "boss_visible" => "d2r.boss.engaged",
      "boss_dead" => "d2r.boss.slain",
      "death_screen" => "d2r.player.died",
      "loading_screen" => "d2r.loading.started",
      "character_select" => "d2r.character.selection.visible",
      "character_creation" => "d2r.character.creation.visible",
      "game_creation" => "d2r.game.creation.visible"
    }.freeze

    def initialize(window_size: 3, confirmations: 2, immediate_confidence: 0.9)
      @window_size = Integer(window_size)
      @confirmations = Integer(confirmations)
      @immediate_confidence = Float(immediate_confidence)
      @history = Hash.new { |hash, key| hash[key] = [] }
      @stable = {}
      @game_lifecycle = :outside
    end

    def observe(classification, observed_at: Time.now.utc.iso8601(6))
      classification.fetch("signals").flat_map do |group, signal|
        observe_signal(group:, signal:, observed_at:)
      end
    end

    def snapshot
      @stable.dup
    end

    private

    def observe_signal(group:, signal:, observed_at:)
      state = signal.fetch("state")
      return [] if state == "unknown"

      history = @history[group]
      history << state
      history.shift while history.size > @window_size
      stable_state = confirmed_state(group, signal, history)
      return [] unless stable_state

      previous = @stable[group]
      return [] if previous == stable_state

      @stable[group] = stable_state
      payload = {
        "group" => group,
        "previous" => previous,
        "current" => stable_state,
        "confidence" => signal.fetch("confidence"),
        "observed_at" => observed_at
      }
      events = [ { "type" => "d2r.state.changed", "payload" => payload } ]
      events.concat(domain_events(group:, previous:, current: stable_state, payload:))
      events.concat(lifecycle_events(group:, previous:, current: stable_state, payload:))
      events
    end

    def confirmed_state(group, signal, history)
      state = signal.fetch("state")
      if group == "screen" && IMMEDIATE_SCREEN_STATES.include?(state) && signal.fetch("confidence") >= @immediate_confidence
        return state
      end
      required_confirmations = if group == "screen" && HIGH_RISK_SCREEN_STATES.include?(state)
        @window_size
      else
        @confirmations
      end
      state if history.count(state) >= required_confirmations
    end

    def domain_events(group:, previous:, current:, payload:)
      return [] unless group == "screen"

      events = []
      events << { "type" => "d2r.loading.finished", "payload" => payload } if previous == "loading_screen" && current != "loading_screen"
      events << { "type" => DOMAIN_EVENTS.fetch(current), "payload" => payload } if DOMAIN_EVENTS.key?(current)
      events
    end

    def lifecycle_events(group:, previous:, current:, payload:)
      return [] unless group == "screen"

      events = []
      if %w[character_select character_creation game_creation].include?(current)
        events << { "type" => "d2r.game.ended", "payload" => payload } if @game_lifecycle == :in_game
        @game_lifecycle = :armed
      elsif current == "loading_screen" && @game_lifecycle == :armed
        @game_lifecycle = :entry_loading
      elsif previous == "loading_screen" && @game_lifecycle == :entry_loading && %w[gameplay area_banner boss_visible boss_dead death_screen].include?(current)
        @game_lifecycle = :in_game
        events << {
          "type" => "d2r.game.started",
          "payload" => {
            "game_id" => "visual-#{payload.fetch("observed_at")}",
            "boundary" => "character_select_loading_gameplay",
            "observed_at" => payload.fetch("observed_at")
          }
        }
      elsif previous.nil? && @game_lifecycle == :outside && %w[gameplay area_banner boss_visible boss_dead death_screen].include?(current)
        # A worker can restart while the player remains in game. Recover the
        # lifecycle from the first confirmed gameplay state instead of waiting
        # for another character-select/loading boundary.
        @game_lifecycle = :in_game
        events << {
          "type" => "d2r.game.started",
          "payload" => {
            "game_id" => "visual-#{payload.fetch("observed_at")}",
            "boundary" => "observer_started_in_game",
            "observed_at" => payload.fetch("observed_at")
          }
        }
      end
      events
    end
  end
end
