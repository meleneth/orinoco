# frozen_string_literal: true

require "rails_helper"
require "orinoco/pipeline/event"

RSpec.describe TankGame::Handler do
  class TankGameHandlerSpecRedis
    attr_reader :values

    def initialize
      @values = {}
    end

    def get(key)
      values[key]
    end

    def set(key, value)
      values[key] = value
    end
  end

  class TankGameHandlerSpecPublisher
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(type, payload = {}, **options)
      events << { type: type, payload: payload, options: options }
    end
  end

  let(:redis) { TankGameHandlerSpecRedis.new }
  let(:publisher) { TankGameHandlerSpecPublisher.new }
  let(:broadcaster) { class_double(Turbo::StreamsChannel).as_stubbed_const }
  let(:config) { AffordanceConfig.default_config_for(:tank_game) }
  let(:handler) do
    described_class.new(
      redis: redis,
      publisher: publisher,
      broadcaster: broadcaster,
      config_reader: -> { config },
      external_base_url: "http://example.test"
    )
  end

  before do
    allow(broadcaster).to receive(:broadcast_update_to)
  end

  it "starts setup for moderator trigger and asks OBS for the current scene" do
    event = Orinoco::Pipeline::Event.build(
      "twitch.chat.message_received",
      {
        "tags" => { "display_name" => "Mod", "mod" => true },
        "name" => "mod",
        "txt" => "!TankGame",
        "twitch_emotes" => []
      }
    )

    handler.handle_chat_event(event)

    state = JSON.parse(redis.values.fetch(TankGame::StateStore::KEY))
    expect(state["phase"]).to eq("setup_pending")
    expect(publisher.events.first).to include(type: "obs.command.requested")
    expect(publisher.events.first.dig(:payload, "request", "requestType")).to eq("GetCurrentProgramScene")
    expect(publisher.events.first.dig(:payload, "reply_topic")).to eq(Orinoco::Messaging::Names::OBS_COMMAND_RESULT_TOPIC)
  end

  it "turns OBS current-scene result into setup commands and signup state" do
    redis.set(
      TankGame::StateStore::KEY,
      JSON.generate(
        "phase" => "setup_pending",
        "round_id" => "round-1",
        "setup_request_id" => "req-1",
        "players" => [],
        "tanks" => []
      )
    )
    event = Orinoco::Pipeline::Event.build(
      "obs.command.completed",
      {
        "request" => { "requestType" => "GetCurrentProgramScene", "requestData" => {} },
        "response" => { "currentProgramSceneName" => "Main" }
      },
      correlation: { "request_id" => "req-1" }
    )

    handler.handle_obs_result(event)

    state = JSON.parse(redis.values.fetch(TankGame::StateStore::KEY))
    expect(state).to include("phase" => "signup", "previous_scene_name" => "Main")
    request_types = publisher.events.map { |entry| entry.dig(:payload, "request", "requestType") }
    expect(request_types).to include("CreateScene", "CreateSceneItem", "CreateInput", "SetInputSettings", "SetCurrentProgramScene")
  end
end
