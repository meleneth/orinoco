# frozen_string_literal: true

require "spec_helper"
require "aws-sdk-sqs"
require "obs_bridge/aws_message"
require "obs_bridge/control_message"
require "obs_bridge/control_applier"
require "obs_bridge/control_consumer"

RSpec.describe ObsBridge::ControlConsumer do
  let(:queue_url) { "http://goaws:31040/000000000000/obs_bridge_control" }
  let(:sqs) { instance_double(Aws::SQS::Client) }
  let(:applier) { instance_double(ObsBridge::ControlApplier) }
  let(:message_unwrapper) { class_double(ObsBridge::AwsMessage) }
  let(:message_parser) { class_double(ObsBridge::ControlMessage) }
  let(:logger) { ->(_msg) { } }

  let(:message) { double("sqs message", body: '{"type":"obs.bridge.enable","bridge_id":"main"}', receipt_handle: "rh-1") }
  let(:response) { double("receive_message_response", messages: messages) }
  let(:messages) { [] }

  subject(:consumer) do
    described_class.new(
      sqs: sqs,
      queue_url: queue_url,
      bridge_id: "main",
      applier: applier,
      logger: logger,
      wait_time_seconds: wait_time_seconds,
      max_number_of_messages: max_number_of_messages,
      message_unwrapper: message_unwrapper,
      message_parser: message_parser
    )
  end

  let(:wait_time_seconds) { 20 }
  let(:max_number_of_messages) { 1 }

  before do
    allow(sqs).to receive(:receive_message).and_return(response)
    allow(sqs).to receive(:delete_message)
    allow(applier).to receive(:apply)
  end

  it "long-polls SQS with the configured wait time and max messages" do
    consumer.run_once

    expect(sqs).to have_received(:receive_message).with(
      queue_url: queue_url,
      max_number_of_messages: 1,
      wait_time_seconds: 20
    )
  end

  it "applies a valid message and deletes it" do
    control_message = ObsBridge::ControlMessage::Enable.new(bridge_id: "main", command_id: "abc")
    payload = { "type" => "obs.bridge.enable", "bridge_id" => "main" }
    messages.replace([ message ])

    allow(message_unwrapper).to receive(:unwrap).with(message).and_return(payload)
    allow(message_parser).to receive(:parse).with(payload, expected_bridge_id: "main").and_return(control_message)
    allow(applier).to receive(:apply).with(control_message).and_return(:enabled)

    consumer.run_once

    expect(message_unwrapper).to have_received(:unwrap).with(message)
    expect(message_parser).to have_received(:parse).with(payload, expected_bridge_id: "main")
    expect(applier).to have_received(:apply).with(control_message)
    expect(sqs).to have_received(:delete_message).with(
      queue_url: queue_url,
      receipt_handle: "rh-1"
    )
  end

  it "leaves invalid payloads undeleted" do
    messages.replace([ message ])

    allow(message_unwrapper).to receive(:unwrap).with(message)
      .and_raise(ObsBridge::AwsMessage::InvalidPayload, "bad payload")

    consumer.run_once

    expect(sqs).not_to have_received(:delete_message)
    expect(applier).not_to have_received(:apply)
  end

  it "leaves invalid control messages undeleted" do
    payload = { "type" => "obs.bridge.spaghetti", "bridge_id" => "main" }
    messages.replace([ message ])

    allow(message_unwrapper).to receive(:unwrap).with(message).and_return(payload)
    allow(message_parser).to receive(:parse).with(payload, expected_bridge_id: "main")
      .and_raise(ObsBridge::ControlMessage::Invalid, "unknown type")

    consumer.run_once

    expect(sqs).not_to have_received(:delete_message)
    expect(applier).not_to have_received(:apply)
  end

  it "passes ignored messages to the applier and still deletes them" do
    ignored_message = ObsBridge::ControlMessage::Ignored.new(
      bridge_id: "main",
      actual_bridge_id: "other",
      command_id: "abc"
    )
    payload = { "type" => "obs.bridge.enable", "bridge_id" => "other" }
    messages.replace([ message ])

    allow(message_unwrapper).to receive(:unwrap).with(message).and_return(payload)
    allow(message_parser).to receive(:parse).with(payload, expected_bridge_id: "main").and_return(ignored_message)
    allow(applier).to receive(:apply).with(ignored_message).and_return(:ignored)

    consumer.run_once

    expect(applier).to have_received(:apply).with(ignored_message)
    expect(sqs).to have_received(:delete_message).with(
      queue_url: queue_url,
      receipt_handle: "rh-1"
    )
  end

  it "does not delete a message when the applier raises unexpectedly" do
    control_message = ObsBridge::ControlMessage::Enable.new(bridge_id: "main", command_id: "abc")
    payload = { "type" => "obs.bridge.enable", "bridge_id" => "main" }
    messages.replace([ message ])

    allow(message_unwrapper).to receive(:unwrap).with(message).and_return(payload)
    allow(message_parser).to receive(:parse).with(payload, expected_bridge_id: "main").and_return(control_message)
    allow(applier).to receive(:apply).with(control_message).and_raise(StandardError, "boom")

    consumer.run_once

    expect(sqs).not_to have_received(:delete_message)
  end
end