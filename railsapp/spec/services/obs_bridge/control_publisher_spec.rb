# frozen_string_literal: true

require "spec_helper"
require "json"
require "time"
require "support/fake_sqs_client"
require "obs_bridge/control_publisher"

RSpec.describe ObsBridge::ControlPublisher do
  let(:sqs) { FakeSqsClient.new }
  let(:clock) { -> { Time.utc(2026, 3, 23, 18, 0, 0) } }
  let(:uuid_generator) { -> { "cmd-123" } }

  subject(:publisher) do
    described_class.new(
      sqs: sqs,
      queue_url: "http://goaws:31040/000000000000/obs_bridge_control",
      bridge_id: "main",
      clock: clock,
      uuid_generator: uuid_generator
    )
  end

  it "publishes a start command as an obs.bridge.enable event" do
    payload = publisher.start!

    expect(payload).to include(
      "type" => "obs.bridge.enable",
      "source" => "obs.bridge.control",
      "occurred_at" => "2026-03-23T18:00:00.000000Z"
    )
    expect(payload.fetch("payload")).to include(
      bridge_id: "main",
      command_id: "cmd-123",
      requested_at: "2026-03-23T18:00:00.000000Z"
    )

    expect(JSON.parse(sqs.send_calls.last[:message_body])).to eq(JSON.parse(JSON.generate(payload)))
  end

  it "publishes a stop command as obs.bridge.disable" do
    publisher.stop!

    expect(JSON.parse(sqs.send_calls.last[:message_body]).fetch("type")).to eq("obs.bridge.disable")
  end

  it "publishes a refresh command" do
    publisher.refresh!

    expect(JSON.parse(sqs.send_calls.last[:message_body]).fetch("type")).to eq("obs.bridge.refresh")
  end

  it "publishes capture-all with a duration" do
    publisher.capture_all!(duration_seconds: 600)

    payload = JSON.parse(sqs.send_calls.last[:message_body])
    expect(payload).to include("type" => "obs.bridge.capture_all")
    expect(payload.fetch("payload")).to include("duration_seconds" => 600)
  end

  it "rejects non-positive capture durations" do
    expect do
      publisher.capture_all!(duration_seconds: 0)
    end.to raise_error(ArgumentError, /positive/)
  end
  it "publishes custom bridge control events" do
    publisher = described_class.new(
      sqs: sqs,
      queue_url: "http://goaws:31040/000000000000/twitch_bridge_control",
      bridge_id: "twitch_bridge",
      event_prefix: "twitch.bridge",
      source: "twitch.bridge.control",
      clock: clock,
      uuid_generator: uuid_generator
    )

    payload = publisher.start!

    expect(payload).to include(
      "type" => "twitch.bridge.enable",
      "source" => "twitch.bridge.control"
    )
    expect(payload.fetch("payload")).to include(
      bridge_id: "twitch_bridge",
      command_id: "cmd-123"
    )
  end
end
