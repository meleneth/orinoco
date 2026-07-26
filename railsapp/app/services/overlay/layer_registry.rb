# frozen_string_literal: true

module Overlay
  class LayerRegistry
    Layer = Data.define(:key, :label, :target, :stream)

    DEFAULT_STREAM = "overlay:default"

    LAYERS = [
      Layer.new(
        key: "toasts",
        label: "Toasts",
        target: "overlay_layer_toasts",
        stream: DEFAULT_STREAM
      ),
      Layer.new(
        key: "wos_brain",
        label: "WOSBrain",
        target: "overlay_layer_wos_brain",
        stream: DEFAULT_STREAM
      )
    ].freeze

    def self.layers
      LAYERS
    end

    def self.fetch!(key)
      normalized = key.to_s
      layers.find { |layer| layer.key == normalized } || raise(Overlay::UnknownLayerError, "unknown overlay layer #{key.inspect}")
    end
  end
end
