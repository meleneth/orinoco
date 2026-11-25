# frozen_string_literal: true

require "spec_helper"
require "d2r/observer_control"

RSpec.describe D2r::ObserverControl do
  let(:values) { {} }
  let(:redis) do
    double("redis").tap do |client|
      allow(client).to receive(:get) { |key| values[key] }
      allow(client).to receive(:set) do |key, value, **_options|
        values[key] = value
        "OK"
      end
    end
  end

  subject(:control) { described_class.new(redis:, clock: -> { Time.utc(2026, 11, 24, 20) }) }

  it "defaults to automatic scanning and validates persistent overrides" do
    expect(control.mode).to eq("auto")
    control.mode = "force_on"
    expect(described_class.new(redis:).mode).to eq("force_on")
    expect { control.mode = "invalid" }.to raise_error(ArgumentError)
    expect(control.mode).to eq("force_on")
  end

  it "reports capture, classification and presence separately" do
    control.record_capture(reason: :waiting_for_obs_bridge, source: "D2R")
    control.record_processing(reason: :unchanged, source: "D2R", screen: "gameplay")
    values["#{D2r::ScanPresence::KEY_PREFIX}D2R"] = JSON.generate(
      "active" => true, "misses" => 0, "screen" => "gameplay"
    )

    snapshot = control.snapshot(source: "D2R")
    expect(snapshot.dig(:capture, "reason")).to eq("waiting_for_obs_bridge")
    expect(snapshot.dig(:processing, "screen")).to eq("gameplay")
    expect(snapshot.dig(:presence, "active")).to eq(true)
    expect(snapshot.dig(:capture, "at")).to eq("2026-11-24T20:00:00.000000Z")
  end
end
