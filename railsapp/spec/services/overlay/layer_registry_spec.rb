# frozen_string_literal: true

require "spec_helper"
require "overlay"
require "overlay/layer_registry"

RSpec.describe Overlay::LayerRegistry do
  it "exposes the WOSBrain layer target and stream" do
    layer = described_class.fetch!("wos_brain")

    expect(layer.key).to eq("wos_brain")
    expect(layer.target).to eq("overlay_layer_wos_brain")
    expect(layer.stream).to eq("overlay:default")
  end

  it "rejects unknown layers" do
    expect { described_class.fetch!("missing") }.to raise_error(Overlay::UnknownLayerError)
  end
end