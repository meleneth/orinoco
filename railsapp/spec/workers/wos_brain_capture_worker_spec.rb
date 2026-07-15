# frozen_string_literal: true

require "rails_helper"
require "json"
require "wos/status_store"

RSpec.describe WosBrainCaptureWorker do
  class WosBrainCaptureWorkerSpecRedis
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

  class WosBrainCaptureWorkerSpecSns
    attr_reader :publish_calls

    def initialize
      @publish_calls = []
    end

    def publish(**kwargs)
      @publish_calls << kwargs
    end
  end

  class WosBrainCaptureWorkerSpecTopology
    def topic_arn(name)
      "arn:#{name}"
    end
  end

  let(:redis) { WosBrainCaptureWorkerSpecRedis.new }
  let(:sns) { WosBrainCaptureWorkerSpecSns.new }
  let(:topology) { WosBrainCaptureWorkerSpecTopology.new }
  let(:obs_status_reader) do
    instance_double(
      ObsBridge::StatusReader,
      snapshot: { status: { connected: true } }
    )
  end

  before do
    @original_topology = Rails.configuration.x.orinoco.messaging_topology

    AffordanceConfig.fetch!(:wos_brain).update!(
      enabled: true,
      config: AffordanceConfig.default_config_for(:wos_brain).merge(
        "enabled" => true,
        "screenshot_source_name" => "Display Capture"
      )
    )

    allow(Redis).to receive(:new).and_return(redis)
    allow(Aws::SNS::Client).to receive(:new).and_return(sns)
    allow(ObsBridge::StatusReader).to receive(:new).and_return(obs_status_reader)
    Rails.configuration.x.orinoco.messaging_topology = topology
  end

  after do
    Rails.configuration.x.orinoco.messaging_topology = @original_topology
  end

  it "publishes an OBS screenshot command for the configured WOS source and records status" do
    described_class.new.run_once

    expect(sns.publish_calls.length).to eq(1)
    expect(sns.publish_calls.first.fetch(:topic_arn)).to eq("arn:orinoco.obs.command")

    message = JSON.parse(sns.publish_calls.first.fetch(:message))
    expect(message).to include(
      "type" => "obs.command.requested",
      "source" => "obs.screenshot.requester"
    )
    expect(message.dig("payload", "request", "requestType")).to eq("GetSourceScreenshot")
    request_data = message.dig("payload", "request", "requestData")
    expect(request_data).to include(
      "sourceName" => "Display Capture",
      "imageWidth" => 1280,
      "imageHeight" => 720
    )

    status = JSON.parse(redis.values.fetch(Wos::StatusStore::KEY))
    expect(status).to include(
      "state" => "capture_requested",
      "screenshot_source_name" => "Display Capture"
    )
    expect(status.fetch("last_request_id")).to be_present
  end
end