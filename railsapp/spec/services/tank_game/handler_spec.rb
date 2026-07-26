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

  class TankGameHandlerSpecScheduler
    attr_reader :calls

    def initialize
      @calls = []
    end

    def schedule!(state, run_at:, reason:)
      calls << { state: state, run_at: run_at, reason: reason }
    end
  end

  class TankGameHandlerSpecToasts
    attr_reader :messages

    def initialize
      @messages = []
    end

    def broadcast!(message:, tone:, title:)
      messages << { message: message, tone: tone, title: title }
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
  let(:tick_scheduler) { TankGameHandlerSpecScheduler.new }
  let(:toast_broadcaster) { TankGameHandlerSpecToasts.new }
  let(:broadcaster) { class_double(Turbo::StreamsChannel).as_stubbed_const }
  let(:config) { AffordanceConfig.default_config_for(:tank_game) }
  let(:handler) do
    described_class.new(
      redis: redis,
      publisher: publisher,
      broadcaster: broadcaster,
      config_reader: -> { config },
      external_base_url: "http://example.test",
      tick_scheduler: tick_scheduler,
      toast_broadcaster: toast_broadcaster
    )
  end

  before do
    allow(broadcaster).to receive(:broadcast_replace_to)
  end


  it "broadcasts overlay replacements so animations reconnect" do
    event = Orinoco::Pipeline::Event.build(
      "twitch.chat.message_received",
      {
        "tags" => { "display_name" => "One" },
        "name" => "one",
        "txt" => "!signup",
        "twitch_emotes" => []
      }
    )
    redis.set(
      TankGame::StateStore::KEY,
      JSON.generate(
        "phase" => "signup",
        "round_id" => "round-1",
        "players" => [],
        "tanks" => []
      )
    )

    handler.handle_chat_event(event)

    expect(broadcaster).to have_received(:broadcast_replace_to).with(
      "tank_game:overlay",
      target: "tank_game_overlay",
      layout: false,
      renderable: an_instance_of(TankGameOverlayComponent)
    )
  end

  it "broadcasts TankGame lifecycle toasts" do
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

    expect(toast_broadcaster.messages.last).to include(
      message: "Mod requested TankGame",
      title: "TankGame",
      tone: "info"
    )
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


  it "starts demo setup for moderator trigger" do
    event = Orinoco::Pipeline::Event.build(
      "twitch.chat.message_received",
      {
        "tags" => { "display_name" => "Mod", "mod" => true },
        "name" => "mod",
        "txt" => "!TankDemo",
        "twitch_emotes" => []
      }
    )

    handler.handle_chat_event(event)

    state = JSON.parse(redis.values.fetch(TankGame::StateStore::KEY))
    expect(state).to include("phase" => "setup_pending", "demo" => true)
    expect(publisher.events.first.dig(:payload, "request", "requestType")).to eq("GetCurrentProgramScene")
  end

  it "starts demo overlay-only when the OBS bridge is unavailable" do
    offline_handler = described_class.new(
      redis: redis,
      publisher: publisher,
      broadcaster: broadcaster,
      config_reader: -> { config },
      external_base_url: "http://example.test",
      tick_scheduler: tick_scheduler,
      toast_broadcaster: toast_broadcaster,
      obs_bridge_available: -> { false }
    )
    event = Orinoco::Pipeline::Event.build(
      "twitch.chat.message_received",
      {
        "tags" => { "display_name" => "Mod", "mod" => true },
        "name" => "mod",
        "txt" => "!TankDemo",
        "twitch_emotes" => []
      }
    )

    offline_handler.handle_chat_event(event)

    state = JSON.parse(redis.values.fetch(TankGame::StateStore::KEY))
    expect(state).to include("phase" => "active", "demo" => true, "obs_setup" => "unavailable")
    expect(state["status"]).to include("overlay only")
    expect(state["players"].length).to eq(10)
    expect(publisher.events).to be_empty
    expect(tick_scheduler.calls.last).to include(reason: "combat_tick")
  end

  it "recovers stuck setup as overlay-only when OBS is unavailable and TankDemo is triggered again" do
    redis.set(
      TankGame::StateStore::KEY,
      JSON.generate(
        "phase" => "setup_pending",
        "demo" => true,
        "round_id" => "round-1",
        "setup_request_id" => "req-1",
        "players" => [],
        "tanks" => []
      )
    )
    offline_handler = described_class.new(
      redis: redis,
      publisher: publisher,
      broadcaster: broadcaster,
      config_reader: -> { config },
      tick_scheduler: tick_scheduler,
      toast_broadcaster: toast_broadcaster,
      obs_bridge_available: -> { false }
    )
    event = Orinoco::Pipeline::Event.build(
      "twitch.chat.message_received",
      {
        "tags" => { "display_name" => "Mod", "mod" => true },
        "name" => "mod",
        "txt" => "!TankDemo",
        "twitch_emotes" => []
      }
    )

    offline_handler.handle_chat_event(event)

    state = JSON.parse(redis.values.fetch(TankGame::StateStore::KEY))
    expect(state).to include("phase" => "active", "demo" => true, "obs_setup" => "unavailable")
    expect(publisher.events).to be_empty
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
    create_scene_item = publisher.events.find { |entry| entry.dig(:payload, "request", "requestType") == "CreateSceneItem" }
    expect(create_scene_item.dig(:payload, "request", "requestData", "sceneItemTransform")).to include(
      "positionX" => 0,
      "positionY" => 0,
      "boundsType" => "OBS_BOUNDS_STRETCH",
      "boundsWidth" => 1920,
      "boundsHeight" => 1080
    )
    create_input = publisher.events.find { |entry| entry.dig(:payload, "request", "requestType") == "CreateInput" }
    expect(create_input.dig(:payload, "request", "requestData", "sceneItemTransform")).to include(
      "positionX" => 0,
      "positionY" => 0,
      "boundsType" => "OBS_BOUNDS_STRETCH",
      "boundsWidth" => 1920,
      "boundsHeight" => 1080
    )
  end


  it "resizes existing TankGame scene items during setup" do
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
    inventory_reader = instance_double(
      ObsBridge::InventoryReader,
      scenes: [ { "sceneName" => "TankGame" } ]
    )
    allow(inventory_reader).to receive(:scene_items).with("TankGame").and_return(
      [
        { "sceneItemId" => 11, "sourceName" => "Main" },
        { "sceneItemId" => 12, "sourceName" => "TankGameWebView" }
      ]
    )
    existing_handler = described_class.new(
      redis: redis,
      publisher: publisher,
      broadcaster: broadcaster,
      config_reader: -> { config },
      inventory_reader: inventory_reader,
      tick_scheduler: tick_scheduler,
      toast_broadcaster: toast_broadcaster
    )
    event = Orinoco::Pipeline::Event.build(
      "obs.command.completed",
      {
        "request" => { "requestType" => "GetCurrentProgramScene", "requestData" => {} },
        "response" => { "currentProgramSceneName" => "Main" }
      },
      correlation: { "request_id" => "req-1" }
    )

    existing_handler.handle_obs_result(event)

    transform_ids = publisher.events.filter_map do |entry|
      next unless entry.dig(:payload, "request", "requestType") == "SetSceneItemTransform"

      entry.dig(:payload, "request", "requestData", "sceneItemId")
    end
    expect(transform_ids).to contain_exactly(11, 12)
  end

  it "turns OBS current-scene result into demo state and schedules combat" do
    redis.set(
      TankGame::StateStore::KEY,
      JSON.generate(
        "phase" => "setup_pending",
        "demo" => true,
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
    expect(state).to include("phase" => "active", "demo" => true, "previous_scene_name" => "Main")
    expect(state["players"].length).to eq(10)
    expect(tick_scheduler.calls.last).to include(reason: "combat_tick")
  end

  it "broadcasts volley toasts from delayed tick events" do
    state = {
      "phase" => "active",
      "round_id" => "round-1",
      "round_ends_at" => "2026-07-25T20:10:00Z",
      "next_fire_at" => "2026-07-25T20:00:00Z",
      "players" => [
        { "login" => "one", "display_name" => "One", "health" => 100, "active" => true, "angle" => 45, "power" => 55, "weapon" => 1 },
        { "login" => "two", "display_name" => "Two", "health" => 100, "active" => true, "angle" => 135, "power" => 55, "weapon" => 1 }
      ],
      "tanks" => [
        { "login" => "one", "x" => 100, "y" => 780, "turret_x" => 100, "turret_y" => 758 },
        { "login" => "two", "x" => 1820, "y" => 780, "turret_x" => 1820, "turret_y" => 758 }
      ],
      "terrain" => [ { "x" => 0, "y" => 860 }, { "x" => 1920, "y" => 860 } ],
      "last_volley" => nil
    }
    redis.set(TankGame::StateStore::KEY, JSON.generate(state))
    tick_handler = described_class.new(
      redis: redis,
      publisher: publisher,
      broadcaster: broadcaster,
      engine: TankGame::Engine.new(clock: -> { Time.utc(2026, 7, 25, 20, 0, 0) }, id_generator: -> { "volley-1" }),
      config_reader: -> { config },
      tick_scheduler: tick_scheduler,
      toast_broadcaster: toast_broadcaster
    )
    event = Orinoco::Pipeline::Event.build("tank_game.tick", { "round_id" => "round-1" })

    tick_handler.handle_tick_event(event)

    expect(toast_broadcaster.messages).to include(
      hash_including(message: "Volley fired: 2 shots", title: "TankGame", tone: "warning")
    )
  end

  it "handles delayed tick events and schedules the next combat tick" do
    base_engine = TankGame::Engine.new(clock: -> { Time.utc(2026, 7, 25, 20, 0, 0) }, id_generator: -> { "id-1" })
    state = base_engine.start_setup(
      state: {},
      trigger: TwitchChatBridge::Message.new(tags: { display_name: "Mod", mod: true }, name: "mod", txt: "!TankGame"),
      config: config,
      request_id: "req-1"
    )
    state = base_engine.begin_signup(state: state, previous_scene_name: "Main", config: config)
    state = base_engine.add_player(state: state, message: TwitchChatBridge::Message.new(tags: { display_name: "One" }, name: "one", txt: "!signup"))
    state = base_engine.add_player(state: state, message: TwitchChatBridge::Message.new(tags: { display_name: "Two" }, name: "two", txt: "!signup"))
    redis.set(TankGame::StateStore::KEY, JSON.generate(state))

    tick_handler = described_class.new(
      redis: redis,
      publisher: publisher,
      broadcaster: broadcaster,
      engine: TankGame::Engine.new(clock: -> { Time.utc(2026, 7, 25, 20, 0, 31) }, id_generator: -> { "id-2" }),
      config_reader: -> { config },
      tick_scheduler: tick_scheduler,
      toast_broadcaster: toast_broadcaster
    )
    event = Orinoco::Pipeline::Event.build(
      "tank_game.tick",
      { "round_id" => state.fetch("round_id"), "reason" => "signup_closed" },
      correlation: { "round_id" => state.fetch("round_id") }
    )

    tick_handler.handle_tick_event(event)

    next_state = JSON.parse(redis.values.fetch(TankGame::StateStore::KEY))
    expect(next_state["phase"]).to eq("active")
    expect(tick_scheduler.calls.last).to include(reason: "combat_tick")
    expect(tick_scheduler.calls.last.fetch(:run_at)).to eq(Time.utc(2026, 7, 25, 20, 1, 1))
  end
end
