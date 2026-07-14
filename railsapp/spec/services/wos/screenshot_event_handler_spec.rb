# frozen_string_literal: true

require "spec_helper"
require "base64"
require "orinoco/pipeline/event"
require "wos/screenshot_event_handler"

RSpec.describe Wos::ScreenshotEventHandler do
  class ScreenshotEventHandlerContext
    attr_reader :published

    def initialize
      @published = []
    end

    def publish(type, payload = {}, **options)
      @published << { type: type, payload: payload, options: options }
    end
  end


  let(:config) { double("wos config", enabled?: true, screenshot_source_name: "", config: { "ruleset_mode" => "auto" }) }
  let(:recognizer) { double("recognizer") }
  let(:context) { ScreenshotEventHandlerContext.new }
  let(:event) do
    Orinoco::Pipeline::Event.build(
      "obs.screenshot.captured",
      {
        "imageData" => "data:image/png;base64,#{Base64.strict_encode64("png-bytes")}",
        "imageFormat" => "png",
        "sourceName" => "wos browser source",
        "activeSceneName" => "Game",
        "captureDurationMs" => 12.5
      },
      correlation: { "request_id" => "req-1" }
    )
  end

  it "decodes screenshot image data, runs recognition, and publishes a recognized board event" do
    seen_path = nil
    allow(recognizer).to receive(:call) do |path|
      seen_path = path
      expect(File.binread(path)).to eq("png-bytes")
      double(
        to_h: {
          ruleset: { mode: "base" },
          letters: [{ index: 0, char: "A" }]
        }
      )
    end

    handler = described_class.new(
      config_reader: -> { config },
      recognizer_factory: ->(_config) { recognizer }
    )

    expect(handler.call(event, context)).to eq(:recognized)
    expect(File).not_to exist(seen_path)
    expect(context.published.length).to eq(1)
    expect(context.published.first).to include(type: "wos.board.recognized")
    expect(context.published.first.fetch(:options)).to include(correlation: { "request_id" => "req-1" })
    expect(context.published.first.dig(:payload, "screenshot")).to include(
      "sourceName" => "wos browser source",
      "activeSceneName" => "Game"
    )
    expect(context.published.first.dig(:payload, "recognition", "ruleset")).to include("mode" => "base")
  end

  it "ignores screenshots from other sources when a source is configured" do
    source_config = double("wos config", enabled?: true, screenshot_source_name: "Display Capture")
    handler = described_class.new(
      config_reader: -> { source_config },
      recognizer_factory: ->(_config) { raise "should not build recognizer" }
    )

    expect(handler.call(event, context)).to eq(:ignored_source)
    expect(context.published).to be_empty
  end

  it "does not process screenshots when WOSBrain is disabled" do
    disabled_config = double("wos config", enabled?: false)
    handler = described_class.new(
      config_reader: -> { disabled_config },
      recognizer_factory: ->(_config) { raise "should not build recognizer" }
    )

    expect(handler.call(event, context)).to eq(:disabled)
    expect(context.published).to be_empty
  end

  it "raises on malformed screenshot data so the message is not deleted" do
    malformed_event = Orinoco::Pipeline::Event.build(
      "obs.screenshot.captured",
      { "imageData" => "not base64", "imageFormat" => "png" }
    )
    handler = described_class.new(
      config_reader: -> { config },
      recognizer_factory: ->(_config) { recognizer }
    )

    expect { handler.call(malformed_event, context) }.to raise_error(ArgumentError, /invalid screenshot imageData/)
  end
end