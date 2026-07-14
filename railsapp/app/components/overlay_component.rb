# frozen_string_literal: true

class OverlayComponent < ApplicationComponent
  def initialize(layers:, wos_state: nil)
    @layers = layers
    @wos_state = wos_state
  end

  private

  attr_reader :layers, :wos_state

  def stream_names
    layers.map(&:stream).uniq
  end

  def render_layer(layer)
    case layer.key
    when "wos_brain"
      render WosOverlayLayerComponent.new(state: wos_state)
    else
      ""
    end
  end
end