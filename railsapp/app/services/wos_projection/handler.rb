# frozen_string_literal: true

require_relative "../wos/accepted_word_learner"
require_relative "../wos/accepted_guess_matcher"

module WosProjection
  class Handler
    def initialize(
      redis:,
      broadcaster: Turbo::StreamsChannel,
      accepted_word_learner: Wos::AcceptedWordLearner.new,
      accepted_guess_matcher: Wos::AcceptedGuessMatcher.new(redis: redis),
      status_store: nil
    )
      @store = Wos::OverlayStateStore.new(redis: redis)
      @broadcaster = broadcaster
      @accepted_word_learner = accepted_word_learner
      @accepted_guess_matcher = accepted_guess_matcher
      @status_store = status_store
    end

    def call(event)
      previous_state = @store.read
      state = state_for(event)
      unless active_board?(state)
        @status_store&.no_active_board!
        return previous_state
      end

      accepted_guesses = @accepted_guess_matcher.call(previous_state: previous_state, current_state: state)
      append_accepted_guesses!(state, accepted_guesses)
      @store.write!(state)
      learn_accepted_words(state, accepted_guesses: accepted_guesses)
      broadcast_state(state)
      @status_store&.projection_succeeded!
      state
    rescue StandardError => e
      @status_store&.projection_failed!("WOSBrain projection failed: #{e.class}: #{e.message}")
      raise
    end

    private

    attr_reader :accepted_word_learner

    def active_board?(state)
      Array(state.dig("recognition", "letters")).any? { |tile| tile["char"].to_s.match?(/[A-Z]/i) }
    end

    def append_accepted_guesses!(state, accepted_guesses)
      return if accepted_guesses.empty?

      recognition = state.fetch("recognition", {})
      recognition["solved_words"] = Array(recognition["solved_words"]) + accepted_guesses
    end

    def learn_accepted_words(state, accepted_guesses:)
      recognition = state.fetch("recognition", {})
      accepted_word_learner.call(
        recognition: recognition.merge("solved_words" => screen_solved_words(recognition)),
        observed_at: state["recognized_at"]
      )
      return if accepted_guesses.empty?

      accepted_word_learner.call(
        recognition: { "solved_words" => accepted_guesses },
        observed_at: state["recognized_at"],
        source: Wos::AcceptedGuessMatcher::SOURCE
      )
    end

    def screen_solved_words(recognition)
      Array(recognition["solved_words"]).reject { |row| row["source"] == Wos::AcceptedGuessMatcher::SOURCE }
    end

    def state_for(event)
      event.payload.merge(
        "recognized_at" => event.occurred_at
      )
    end

    def broadcast_state(state)
      layer = Overlay::LayerRegistry.fetch!("wos_brain")

      Rails.application.reloader.wrap do
        @broadcaster.broadcast_update_to(
          layer.stream,
          target: layer.target,
          layout: false,
          renderable: WosOverlayLayerComponent.new(state: state)
        )
      end
    end
  end
end
