# frozen_string_literal: true

module Overlay
  class ToastBroadcaster
    STREAM = Overlay::LayerRegistry::DEFAULT_STREAM
    TARGET = "overlay_layer_toasts"

    def initialize(broadcaster: Turbo::StreamsChannel)
      @broadcaster = broadcaster
    end

    def broadcast!(message:, tone: "info", title: "Orinoco")
      Rails.application.reloader.wrap do
        broadcaster.broadcast_append_to(
          STREAM,
          target: TARGET,
          layout: false,
          renderable: OverlayToastComponent.new(message: message, tone: tone, title: title)
        )
      end
    rescue StandardError => e
      Rails.logger.warn("[overlay-toast] broadcast failed: #{e.class}: #{e.message}")
    end

    private

    attr_reader :broadcaster
  end
end
