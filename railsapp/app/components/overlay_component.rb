# frozen_string_literal: true

class OverlayComponent < ApplicationComponent
  def initialize(layers:, wos_state: nil, d2r_state: nil)
    @layers = layers
    @wos_state = wos_state
    @d2r_state = d2r_state
  end

  private

  attr_reader :layers, :wos_state, :d2r_state

  def stream_names
    layers.map(&:stream).uniq
  end

  def layer_class(layer)
    if layer.key == "toasts"
      "pointer-events-none absolute bottom-8 left-8 right-8 z-[1000] flex flex-col-reverse items-start"
    else
      "pointer-events-none absolute inset-0"
    end
  end

  def render_layer(layer)
    case layer.key
    when "d2r_run"
      render D2rRunOverlayComponent.new(state: d2r_state)
    when "wos_brain"
      render WosOverlayLayerComponent.new(state: wos_state)
    else
      ""
    end
  end
end
