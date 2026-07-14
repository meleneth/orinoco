# frozen_string_literal: true

require "rails_helper"
require "json"
require "support/fake_sqs_client"

RSpec.describe TwitchBridgeWorker do
  class TwitchBridgeWorkerFakeRedis
    def initialize
      @hashes = Hash.new { |hash, key| hash[key] = {} }
    end

    def hgetall(key)
      @hashes[key]
    end

    def hset(key, attributes)
      @hashes[key].merge!(attributes)
      true
    end

    def get(_key)
      nil
    end
  end

  let(:redis) { TwitchBridgeWorkerFakeRedis.new }
  let(:sqs) { FakeSqsClient.new(receive_batches: [[message]]) }
  let(:runtime) { instance_double(TwitchChatBridge::Runtime, start!: true, running?: true, stop!: true) }
  let(:topology) do
    Class.new do
      def queue_url(name)
        "http://goaws:31040/000000000000/#{name}"
      end
    end.new
  end

  before do
    allow(Redis).to receive(:new).and_return(redis)
    allow(Aws::SQS::Client).to receive(:new).and_return(sqs)
    allow(Aws::SNS::Client).to receive(:new).and_return(double("sns"))
    allow(ObsBridge::StatusBroadcaster).to receive(:new).and_return(double(broadcast!: true))
    allow(TwitchConfig).to receive(:first).and_return(instance_double(TwitchConfig, channel_name: "quantumapprentice"))
    allow(TwitchChatBridge::Runtime).to receive(:new).and_return(runtime)

    Rails.application.config.x.orinoco.messaging_topology = topology
    Rails.application.config.x.event_pipeline.aws_client_options = {
      endpoint: "http://goaws:4100",
      region: "us-east-1",
      access_key_id: "fake",
      secret_access_key: "fake"
    }
  end

  def build_message(type, receipt_handle)
    double(body: event_body(type), receipt_handle: receipt_handle)
  end

  def event_body(type)
    JSON.generate(
      "type" => type,
      "source" => "spec",
      "occurred_at" => "2026-07-11T00:00:00Z",
      "payload" => {},
      "correlation" => {}
    )
  end

  context "when Twitch is enabled" do
    let(:message) { build_message("twitch.bridge.enable", "rh-1") }

    it "starts Twitch and cascades a 7TV bridge enable command" do
      described_class.new.run_once

      sent = JSON.parse(sqs.send_calls.last.fetch(:message_body))
      expect(sqs.send_calls.last.fetch(:queue_url)).to include(Orinoco::Messaging::Names::SEVEN_TV_BRIDGE_CONTROL_QUEUE)
      expect(sent).to include(
        "type" => "7tv.bridge.enable",
        "source" => "7tv.bridge.control"
      )
      expect(sent.fetch("payload")).to include("bridge_id" => SevenTvBridgeWorker::BRIDGE_ID)
      expect(runtime).to have_received(:start!)
    end
  end

  context "when Twitch is disabled" do
    let(:message) { build_message("twitch.bridge.disable", "rh-1") }

    it "cascades a 7TV bridge disable command" do
      described_class.new.run_once

      sent = JSON.parse(sqs.send_calls.last.fetch(:message_body))
      expect(sent).to include(
        "type" => "7tv.bridge.disable",
        "source" => "7tv.bridge.control"
      )
    end
  end
end
