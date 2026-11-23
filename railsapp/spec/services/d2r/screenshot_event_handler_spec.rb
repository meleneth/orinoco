# frozen_string_literal: true

require "spec_helper"
require "base64"
require "orinoco/pipeline/event"
require "d2r/screenshot_event_handler"

RSpec.describe D2r::ScreenshotEventHandler do
  class D2rHandlerContext
    attr_reader :published

    def initialize
      @published = []
    end

    def publish(type, payload, **options)
      @published << { type:, payload:, options: }
    end
  end

  let(:classification) do
    {
      "signals" => { "screen" => { "state" => "death_screen", "confidence" => 0.99 } },
      "elapsed_ms" => 12.0
    }
  end
  let(:classifier) { double("classifier", call: double(to_h: classification)) }
  let(:tracker) do
    double("tracker", observe: [
      { "type" => "d2r.player.died", "payload" => { "group" => "screen", "current" => "death_screen" } }
    ])
  end
  let(:gate) { double("gate", complete!: nil) }
  let(:hud_reader) { double("hud_reader", call: {}) }
  let(:hud_area_reader) { double("hud_area_reader", call: nil) }
  let(:hud_tracker) { double("hud_tracker", observe: []) }
  let(:ground_label_reader) { double("ground_label_reader", call: []) }
  let(:loot_tracker) { double("loot_tracker", observe: []) }
  let(:config) { double("config", enabled?: true, screenshot_source_name: "D2R") }
  let(:context) { D2rHandlerContext.new }
  let(:event) do
    Orinoco::Pipeline::Event.build(
      "obs.screenshot.captured",
      {
        "sourceName" => "D2R", "imageFormat" => "jpg",
        "imageData" => "data:image/jpeg;base64,#{Base64.strict_encode64('jpeg')}"
      },
      correlation: { "request_id" => "req-1" }
    )
  end

  it "classifies matching frames and publishes only tracker changes" do
    handler = described_class.new(config_reader: -> { config }, classifier:, tracker:, hud_reader:, hud_area_reader:, hud_tracker:, ground_label_reader:, loot_tracker:, gate:)

    expect(handler.call(event, context)).to eq(:changed)
    expect(context.published.map { |published| published.fetch(:type) }).to eq([ "d2r.player.died" ])
    expect(context.published.first.dig(:payload, "classification", "screen", "state")).to eq("death_screen")
    expect(context.published.first.fetch(:options)).to include(correlation: { "request_id" => "req-1" })
    expect(gate).to have_received(:complete!).with("req-1")
  end

  it "publishes confirmed HUD changes through the same event pipeline" do
    reading = { "area" => "Catacombs Level 2", "difficulty" => "Hell", "terror_zones" => [ "Dry Hills" ] }
    allow(hud_reader).to receive(:call).and_return(reading)
    allow(hud_tracker).to receive(:observe).and_return([
      { "type" => "d2r.area.changed", "payload" => { "area" => "Catacombs Level 2" } }
    ])
    allow(tracker).to receive(:observe).and_return([])
    handler = described_class.new(config_reader: -> { config }, classifier:, tracker:, hud_reader:, hud_area_reader:, hud_tracker:, ground_label_reader:, loot_tracker:, gate:)

    expect(handler.call(event, context)).to eq(:changed)
    expect(context.published.first).to include(type: "d2r.area.changed")
    expect(hud_tracker).to have_received(:observe).with(reading, observed_at: event.occurred_at)
  end

  it "prefers a known OCR area over an approximate bitmap match" do
    allow(hud_reader).to receive(:call).and_return({ "area" => "Catacombs Level 3", "difficulty" => "Hell" })
    allow(hud_area_reader).to receive(:call).and_return("Tower Cellar Level 2")
    allow(tracker).to receive(:observe).and_return([])
    handler = described_class.new(config_reader: -> { config }, classifier:, tracker:, hud_reader:, hud_area_reader:,
      hud_tracker:, ground_label_reader:, loot_tracker:, gate:)

    handler.call(event, context)

    expect(hud_tracker).to have_received(:observe).with(
      { "area" => "Tower Cellar Level 2", "difficulty" => "Hell" },
      observed_at: event.occurred_at
    )
  end

  it "emits confirmed rune and unique sightings through the same event stream" do
    classification["signals"]["screen"]["state"] = "gameplay"
    allow(ground_label_reader).to receive(:call).and_return([
      { "kind" => "rune", "name" => "Ist Rune" },
      { "kind" => "unique", "name" => "Harlequin Crest" }
    ])
    allow(loot_tracker).to receive(:observe).and_return([
      { "type" => "d2r.loot.rune.sighted", "payload" => { "name" => "Ist Rune" } },
      { "type" => "d2r.loot.unique.sighted", "payload" => { "name" => "Harlequin Crest" } }
    ])
    allow(tracker).to receive(:observe).and_return([])
    handler = described_class.new(config_reader: -> { config }, classifier:, tracker:, hud_reader:, hud_area_reader:,
      hud_tracker:, ground_label_reader:, loot_tracker:, gate:)

    expect(handler.call(event, context)).to eq(:changed)
    expect(context.published.map { |item| item.fetch(:type) }).to eq([
      "d2r.loot.rune.sighted", "d2r.loot.unique.sighted"
    ])
    expect(ground_label_reader).to have_received(:call)
  end

  it "does not treat inventory or stash labels as ground drops" do
    classification["signals"]["screen"]["state"] = "gameplay"
    classification["signals"]["right_panel"] = { "state" => "inventory" }
    handler = described_class.new(config_reader: -> { config }, classifier:, tracker:, hud_reader:, hud_area_reader:,
      hud_tracker:, ground_label_reader:, loot_tracker:, gate:)
    handler.call(event, context)
    expect(ground_label_reader).not_to have_received(:call)
    expect(loot_tracker).to have_received(:observe).with([], observed_at: event.occurred_at)
  end

  it "ignores frames from another source" do
    other = Orinoco::Pipeline::Event.build("obs.screenshot.captured", { "sourceName" => "WOS" })
    handler = described_class.new(config_reader: -> { config }, classifier:, tracker:, hud_reader:, hud_area_reader:, hud_tracker:, ground_label_reader:, loot_tracker:, gate:)

    expect(handler.call(other, context)).to eq(:ignored_source)
    expect(classifier).not_to have_received(:call)
  end


  it "does no work while the affordance is disabled" do
    disabled = double("config", enabled?: false)
    handler = described_class.new(config_reader: -> { disabled }, classifier:, tracker:, hud_reader:, hud_area_reader:, hud_tracker:, ground_label_reader:, loot_tracker:, gate:)

    expect(handler.call(event, context)).to eq(:disabled)
    expect(classifier).not_to have_received(:call)
  end
end
