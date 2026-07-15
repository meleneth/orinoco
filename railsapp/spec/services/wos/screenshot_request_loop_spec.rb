# frozen_string_literal: true

require "spec_helper"
require "wos/screenshot_request_loop"
require "wos/status_store"

RSpec.describe Wos::ScreenshotRequestLoop do
  class ScreenshotRequestLoopSpecRedis
    attr_reader :values

    def initialize
      @values = {}
    end

    def get(key)
      @values[key]
    end

    def set(key, value)
      @values[key] = value
    end
  end

  let(:redis) { ScreenshotRequestLoopSpecRedis.new }
  let(:status_store) { Wos::StatusStore.new(redis: redis, clock: -> { Time.utc(2026, 7, 13, 8, 0, 0) }) }
  let(:publisher) { double("screenshot publisher") }
  let(:config) { double("config", enabled?: true, screenshot_source_name: "Display Capture") }

  subject(:loop) do
    described_class.new(
      config_reader: -> { config },
      publisher: publisher,
      status_store: status_store,
      sleeper: ->(_seconds) {},
      logger: ->(_message) {}
    )
  end

  it "publishes a screenshot command for the configured source" do
    event = double(correlation: { "request_id" => "req-1" })
    allow(publisher).to receive(:publish!).and_return(event)

    loop.run_once

    expect(publisher).to have_received(:publish!).with(source_name: "Display Capture", width: 1280, height: 720)
    status = status_store.read
    expect(status).to include(
      "state" => "capture_requested",
      "screenshot_source_name" => "Display Capture",
      "last_request_id" => "req-1"
    )
  end

  it "does not publish when disabled" do
    disabled = double("config", enabled?: false, screenshot_source_name: "Display Capture")
    loop = described_class.new(config_reader: -> { disabled }, publisher: publisher, status_store: status_store)

    expect(publisher).not_to receive(:publish!)
    loop.run_once

    expect(status_store.read).to include("state" => "disabled")
  end

  it "does not publish when the OBS bridge is unavailable" do
    loop = described_class.new(
      config_reader: -> { config },
      publisher: publisher,
      status_store: status_store,
      bridge_available: -> { false }
    )

    expect(publisher).not_to receive(:publish!)
    loop.run_once

    expect(status_store.read).to include(
      "state" => "waiting_for_obs_bridge",
      "last_error" => "OBS bridge is not connected"
    )
  end
  it "records missing source when enabled without a source" do
    missing = double("config", enabled?: true, screenshot_source_name: "")
    loop = described_class.new(config_reader: -> { missing }, publisher: publisher, status_store: status_store)

    expect(publisher).not_to receive(:publish!)
    loop.run_once

    expect(status_store.read).to include("state" => "waiting_for_source")
  end
end
