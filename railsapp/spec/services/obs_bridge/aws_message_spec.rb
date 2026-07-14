# frozen_string_literal: true

require "spec_helper"
require "obs_bridge/aws_message"

RSpec.describe ObsBridge::AwsMessage do
  it "unwraps a plain JSON payload" do
    message = double(body: '{"type":"obs.bridge.enable","bridge_id":"main"}')

    expect(described_class.unwrap(message)).to eq(
      "type" => "obs.bridge.enable",
      "bridge_id" => "main"
    )
  end

  it "unwraps an SNS-style notification wrapper" do
    message = double(
      body: {
        "Type" => "Notification",
        "Message" => '{"type":"obs.bridge.capture_all","bridge_id":"main","duration_seconds":900}'
      }.to_json
    )

    expect(described_class.unwrap(message)).to eq(
      "type" => "obs.bridge.capture_all",
      "bridge_id" => "main",
      "duration_seconds" => 900
    )
  end

  it "raises on malformed outer JSON" do
    message = double(body: "{ definitely not json")

    expect do
      described_class.unwrap(message)
    end.to raise_error(ObsBridge::AwsMessage::InvalidPayload, /invalid JSON payload/)
  end

  it "raises on malformed inner SNS Message JSON" do
    message = double(
      body: {
        "Type" => "Notification",
        "Message" => "{ nope"
      }.to_json
    )

    expect do
      described_class.unwrap(message)
    end.to raise_error(ObsBridge::AwsMessage::InvalidPayload, /invalid JSON payload/)
  end
end