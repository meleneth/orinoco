# frozen_string_literal: true

module WosProjection
  class Handler
    def initialize(redis:, broadcaster: Turbo::StreamsChannel)
      @store = Wos::OverlayStateStore.new(redis: redis)
      @broadcaster = broadcaster
    end

    def call(event)
      state = state_for(event)
      @store.write!(state)
      broadcast_state(state)
      state
    end

    private

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