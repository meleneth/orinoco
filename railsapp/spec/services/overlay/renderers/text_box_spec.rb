# frozen_string_literal: true

require "rails_helper"

RSpec.describe Overlay::Renderers::TextBox do
  let(:position) do
    Overlay::Position.new(anchor: "bottom_right", x: 24, y: 24, unit: "px")
  end

  let(:size) do
    Overlay::Size.new(width: 320, height: 80, size_unit: "px")
  end

  let(:element_config) do
    Overlay::ElementConfig.new(
      renderer_key: "text_box",
      element_key: "clip_countdown",
      style_preset: "obs_panel",
      content_template: "Next clip in {{timers.clip_countdown.remaining_label}}",
      position: position,
      size: size
    )
  end

  let(:binding_config) do
    Struct.new(:template).new("Next clip in {{timers.clip_countdown.remaining_label}}")
  end

  it "emits a div with constrained classes, escaped text, and generated position style" do
    renderer = described_class.new(
      element_config: element_config,
      placement: position,
      binding: binding_config,
      context: {
        "timers" => {
          "clip_countdown" => {
            "remaining_label" => "<00:30>"
          }
        }
      }
    )

    html = renderer.render

    expect(html).to include("<div")
    expect(html).to include('class="rounded-xl bg-black/70 p-4 text-white shadow-lg"')
    expect(html).to include('style="position:absolute;right:24px;bottom:24px;width:320px;height:80px;"')
    expect(html).to include("Next clip in &lt;00:30&gt;")
    expect(html).to include('data-element-key="clip_countdown"')
  end

  it "rejects invalid style presets" do
    renderer = described_class.new(
      element_config: Overlay::ElementConfig.new(
        renderer_key: "text_box",
        element_key: "clip_countdown",
        style_preset: "Kernel",
        content_template: "Hello",
        position: position,
        size: size
      ),
      placement: position,
      binding: binding_config,
      context: {}
    )

    expect { renderer.render }.to raise_error(Overlay::InvalidConfigError, /style_preset is invalid/)
  end
end
