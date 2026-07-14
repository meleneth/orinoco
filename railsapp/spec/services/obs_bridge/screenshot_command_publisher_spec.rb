# frozen_string_literal: true

require "spec_helper"
require "obs_bridge/screenshot_command_publisher"

RSpec.describe ObsBridge::ScreenshotCommandPublisher do
  let(:publish_calls) { [] }
  let(:sns) do
    Class.new do
      def initialize(calls)
        @calls = calls
      end

      def publish(**kwargs)
        @calls << kwargs
      end
    end.new(publish_calls)
  end
  let(:topology) do
    Class.new do
      def topic_arn(name)
        "arn:#{name}"
      end
    end.new
  end

  subject(:publisher) do
    described_class.new(
      sns: sns,
      topology: topology,
      uuid_generator: -> { "req-1" }
    )
  end

  it "publishes an enveloped OBS screenshot command" do
    event = publisher.publish!(source_name: "Board", width: 640, height: 360, quality: 80)

    expect(publish_calls.length).to eq(1)
    expect(publish_calls.first.fetch(:topic_arn)).to eq("arn:orinoco.obs.command")

    payload = JSON.parse(publish_calls.first.fetch(:message))
    expect(payload).to include(
      "type" => "obs.command.requested",
      "source" => "obs.screenshot.requester",
      "correlation" => { "request_id" => "req-1" }
    )
    expect(payload.dig("payload", "reply_topic")).to eq("orinoco.obs.screenshot.results")
    expect(payload.dig("payload", "request")).to eq(
      "requestType" => "GetSourceScreenshot",
      "requestData" => {
        "imageFormat" => "png",
        "imageWidth" => 640,
        "imageHeight" => 360,
        "imageCompressionQuality" => 80,
        "sourceName" => "Board"
      }
    )
    expect(event.type).to eq("obs.command.requested")
  end
end