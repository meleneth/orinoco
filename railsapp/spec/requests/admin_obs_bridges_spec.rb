# frozen_string_literal: true

require "rails_helper"
require "json"
require "support/fake_sqs_client"

RSpec.describe "Admin bridge controls", type: :request do
  class BridgeAdminFakeRedis
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

  let(:redis) { BridgeAdminFakeRedis.new }
  let(:sqs) { FakeSqsClient.new }
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
    allow(ObsBridge::StatusBroadcaster).to receive(:new).and_return(double(broadcast!: true))
    Rails.application.config.x.orinoco.messaging_topology = topology
  end

  it "renders Twitch bridge controls without OBS-only controls" do
    get admin_obs_bridge_path("twitch_bridge")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Twitch Bridge Admin")
    expect(response.body).to include("Start bridge")
    expect(response.body).to include("Stop bridge")
    expect(response.body).not_to include("Refresh inventory")
    expect(response.body).not_to include("Capture all events")
  end

  it "publishes Twitch start control messages to the Twitch bridge queue" do
    post start_admin_obs_bridge_path("twitch_bridge")

    expect(response).to redirect_to(admin_obs_bridge_path("twitch_bridge"))
    sent = JSON.parse(sqs.send_calls.last.fetch(:message_body))
    expect(sqs.send_calls.last.fetch(:queue_url)).to include(Orinoco::Messaging::Names::TWITCH_BRIDGE_CONTROL_QUEUE)
    expect(sent).to include(
      "type" => "twitch.bridge.enable",
      "source" => "twitch.bridge.control"
    )
    expect(sent.fetch("payload")).to include("bridge_id" => "twitch_bridge")
  end
end
