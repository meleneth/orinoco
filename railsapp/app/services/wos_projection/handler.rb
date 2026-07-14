# frozen_string_literal: true

require_relative "../wos/accepted_word_learner"

module WosProjection
  class Handler
    def initialize(
      redis:,
      broadcaster: Turbo::StreamsChannel,
      accepted_word_learner: Wos::AcceptedWordLearner.new,
      status_store: nil
    )
      @store = Wos::OverlayStateStore.new(redis: redis)
      @broadcaster = broadcaster
      @accepted_word_learner = accepted_word_learner
      @status_store = status_store
    end

    def call(event)
      state = state_for(event)
      @store.write!(state)
      learn_accepted_words(state)
      broadcast_state(state)
      @status_store&.projection_succeeded!
      state
    rescue StandardError => e
      @status_store&.projection_failed!("WOSBrain projection failed: #{e.class}: #{e.message}")
      raise
    end

    private

    attr_reader :accepted_word_learner

    def learn_accepted_words(state)
      accepted_word_learner.call(
        recognition: state.fetch("recognition", {}),
        observed_at: state["recognized_at"]
      )
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
