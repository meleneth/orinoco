# frozen_string_literal: true

require "spec_helper"
require "d2r/screenshot_request_loop"

RSpec.describe D2r::ScreenshotRequestLoop do
  it "does not request frames while the affordance is disabled" do
    config = double("config", enabled?: false)
    publisher = double("publisher", publish!: nil)
    gate = double("gate")
    loop_service = described_class.new(config_reader: -> { config }, publisher:, gate:)

    expect(loop_service.run_once).to eq(:disabled)
    expect(publisher).not_to have_received(:publish!)
  end

  it "requests bounded JPEG frames and does not queue another while one is in flight" do
    gate = double("gate", pending?: false, requested!: nil)
    event = double("event", correlation: { "request_id" => "req-1" })
    publisher = double("publisher", publish!: event)
    config = double(
      "config", enabled?: true, screenshot_source_name: "D2R",
      config: { "interval_seconds" => 0.5, "image_width" => 640, "image_height" => 400, "jpeg_quality" => 70 }
    )
    loop_service = described_class.new(config_reader: -> { config }, publisher:, gate:)

    expect(loop_service.run_once).to eq(:requested)
    expect(publisher).to have_received(:publish!).with(
      source_name: "D2R", image_format: "jpg", width: 640, height: 400, quality: 70
    )
    expect(gate).to have_received(:requested!).with("req-1")

    allow(gate).to receive(:pending?).and_return(true)
    expect(loop_service.run_once).to eq(:in_flight)
    expect(publisher).to have_received(:publish!).once
  end
end
