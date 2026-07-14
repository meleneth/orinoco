# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ClipShows", type: :request do
  let(:redis_url) { "redis://redis:6379/0" }
  let(:bridge_id) { "obs-main" }
  let(:redis) { instance_double(Redis) }

  let(:inventory_reader) do
    instance_double(
      ObsBridge::InventoryReader,
      scenes: [{ "sceneName" => "Clips" }]
    )
  end

  let(:scene_index) do
    instance_double(
      SceneIndex,
      load_from_inventory!: nil,
      by_name: {}
    )
  end

  let(:sns_client) { instance_double(Aws::SNS::Client) }
  let(:published_messages) { [] }
  let(:aws_client_options) { { region: "us-east-1" } }

  let(:topology) do
    instance_double(
      Orinoco::Messaging::Topology,
      topic_arn: obs_command_topic_arn
    )
  end

  let(:obs_command_topic_arn) do
    "arn:aws:sns:us-east-1:000000000000:obs-command"
  end

  before do
    allow(Rails.configuration.x.scoreboard)
      .to receive(:redis_url)
      .and_return(redis_url)

    allow(Rails.configuration.x.obs_bridge)
      .to receive(:bridge_id)
      .and_return(bridge_id)

    allow(Rails.configuration.x.event_pipeline)
      .to receive(:aws_client_options)
      .and_return(aws_client_options)

    allow(Rails.configuration.x.orinoco)
      .to receive(:messaging_topology)
      .and_return(topology)

    allow(Redis)
      .to receive(:new)
      .with(url: redis_url)
      .and_return(redis)

    allow(ObsBridge::InventoryReader)
      .to receive(:new)
      .with(redis:, bridge_id:)
      .and_return(inventory_reader)

    allow(SceneIndex)
      .to receive(:new)
      .and_return(scene_index)

    allow(sns_client)
      .to receive(:publish) { |kwargs| published_messages << kwargs }

    allow(Aws::SNS::Client)
      .to receive(:new)
      .with(**aws_client_options)
      .and_return(sns_client)
  end

  describe "GET /get_scenes" do
    it "returns http success" do
      get clip_show_get_scenes_path, params: { scenes: "Clips" }

      expect(response).to have_http_status(:success)

      expect(SceneIndex)
        .to have_received(:new)
        .with(scene: "Clips")

      expect(scene_index)
        .to have_received(:load_from_inventory!)
        .with(inventory_reader)
    end
  end

  describe "POST /play" do
    it "emits OBS requests" do
      post clip_show_play_path,
           params: {
             id: 123,
             clip_name: "fight",
             scene_name: "Clips"
           },
           headers: {
             "ACCEPT" => "text/vnd.turbo-stream.html"
           }

      expect(response).to have_http_status(:success)
      payloads = published_messages.map { |message| JSON.parse(message.fetch(:message)) }

      expect(published_messages.map { |message| message.fetch(:topic_arn) }).to all(eq(obs_command_topic_arn))
      expect(payloads.map { |payload| payload.fetch("type") }).to eq([
        "obs.command.requested",
        "obs.command.requested"
      ])
      expect(payloads.map { |payload| payload.fetch("source") }).to eq([
        "clip_show",
        "clip_show"
      ])
      expect(payloads.map { |payload| payload.dig("payload", "request") }).to eq([
        {
          "requestType" => "SetSceneItemEnabled",
          "requestData" => {
            "sceneName" => "Clips",
            "sceneItemId" => 123,
            "sceneItemEnabled" => true
          }
        },
        {
          "requestType" => "SetInputAudioMonitorType",
          "requestData" => {
            "inputName" => "fight",
            "monitorType" => "OBS_MONITORING_TYPE_MONITOR_ONLY"
          }
        }
      ])
    end
  end
end
