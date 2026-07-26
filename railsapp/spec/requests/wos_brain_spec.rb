# frozen_string_literal: true

require "rails_helper"
require "json"

RSpec.describe "WOSBrain", type: :request do
  class WosBrainRequestSpecRedis
    attr_reader :values

    def initialize(values = {})
      @values = values
    end

    def get(key)
      @values[key]
    end

    def set(key, value)
      @values[key] = value
    end

    def hgetall(_key)
      {}
    end
  end

  let(:redis) do
    WosBrainRequestSpecRedis.new(
      Wos::StatusStore::KEY => JSON.generate(
        "state" => "recognized",
        "screenshot_source_name" => "Display Capture",
        "last_request_id" => "req-1",
        "last_capture_requested_at" => "2026-07-13T08:00:00.000000Z",
        "last_recognized_at" => "2026-07-13T08:00:02.000000Z",
        "last_projected_at" => "2026-07-13T08:00:03.000000Z",
        "last_error" => ""
      ),
      Wos::OverlayStateStore::KEY => JSON.generate(
        "recognized_at" => "2026-07-13T08:00:02.000000Z",
        "recognition" => {
          "ruleset" => { "mode" => "base" },
          "letters" => [
            { "index" => 0, "char" => "W" },
            { "index" => 1, "char" => "O" },
            { "index" => 2, "char" => "S" }
          ]
        }
      )
    )
  end

  let(:queue_inspector) do
    instance_double(
      Orinoco::Messaging::QueueInspector,
      queues: [
        Orinoco::Messaging::QueueInspector::QueueSnapshot.new(
          name: Orinoco::Messaging::Names::OBS_BRIDGE_COMMAND_QUEUE,
          url: "http://goaws.example/obs-command",
          arn: "arn:aws:sqs:us-east-1:000000000000:obs-command",
          visible: 0,
          in_flight: 0,
          delayed: 0
        ),
        Orinoco::Messaging::QueueInspector::QueueSnapshot.new(
          name: Orinoco::Messaging::Names::OBS_SCREENSHOT_RESULT_QUEUE,
          url: "http://goaws.example/obs-screenshot-results",
          arn: "arn:aws:sqs:us-east-1:000000000000:obs-screenshot-results",
          visible: 1,
          in_flight: 0,
          delayed: 0
        ),
        Orinoco::Messaging::QueueInspector::QueueSnapshot.new(
          name: Orinoco::Messaging::Names::WOS_BOARD_RECOGNIZED_QUEUE,
          url: "http://goaws.example/wos-board-recognized",
          arn: "arn:aws:sqs:us-east-1:000000000000:wos-board-recognized",
          visible: 0,
          in_flight: 0,
          delayed: 0
        )
      ]
    )
  end
  before do
    AffordanceConfig.fetch!(:wos_brain).update!(
      enabled: true,
      config: AffordanceConfig.default_config_for(:wos_brain).merge(
        "enabled" => true,
        "screenshot_source_name" => "Display Capture",
        "ruleset_mode" => "manual",
        "manual_ruleset" => "base"
      )
    )
    allow(Redis).to receive(:new).and_return(redis)
    allow(Orinoco::Messaging::QueueInspector).to receive(:new).and_return(queue_inspector)
  end

  it "renders WOSBrain configuration, runtime status, and latest projection" do
    get wos_brain_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("WOSBrain")
    expect(response.body).to include("Display Capture")
    expect(response.body).to include("recognized")
    expect(response.body).to include("2026-07-13T08:00:03.000000Z")
    expect(response.body).to include("req-1")
    expect(response.body).to include("WOS")
    expect(response.body).to include("Open /overlay")
    expect(response.body).to include("TankGame Overlay")
    expect(response.body).to include(tank_game_overlay_path)
    expect(response.body).to include("Enable")
    expect(response.body).to include("Disable")
    expect(response.body).to include("OBS Dependency")
    expect(response.body).to include("Pipeline Queues")
  end

  it "enables WOSBrain from the status page" do
    AffordanceConfig.fetch!(:wos_brain).update!(enabled: false)

    post start_wos_brain_path

    expect(response).to redirect_to(wos_brain_path)
    expect(AffordanceConfig.fetch!(:wos_brain)).to be_enabled
  end

  it "disables WOSBrain from the status page" do
    post stop_wos_brain_path

    expect(response).to redirect_to(wos_brain_path)
    expect(AffordanceConfig.fetch!(:wos_brain)).not_to be_enabled
    expect(JSON.parse(redis.values.fetch(Wos::StatusStore::KEY))).to include("state" => "disabled")
  end
end
