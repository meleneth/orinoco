# frozen_string_literal: true

require "rails_helper"

RSpec.describe TankGame::Engine do
  subject(:engine) { described_class.new(clock: clock, id_generator: id_generator) }

  let(:now) { Time.utc(2026, 7, 25, 20, 0, 0) }
  let(:clock) { -> { now } }
  let(:id_generator) { -> { "round-1" } }
  let(:config) { AffordanceConfig.default_config_for(:tank_game) }
  let(:starter) { TwitchChatBridge::Message.new(tags: { display_name: "Mod", mod: true }, name: "mod", txt: "!TankGame") }
  let(:player_one) { TwitchChatBridge::Message.new(tags: { display_name: "One" }, name: "one", txt: "!signup") }
  let(:player_two) { TwitchChatBridge::Message.new(tags: { display_name: "Two" }, name: "two", txt: "!signup") }

  it "moves from setup to signup to active terrain/tank state" do
    state = engine.start_setup(state: {}, trigger: starter, config: config, request_id: "req-1")
    state = engine.begin_signup(state: state, previous_scene_name: "Main", config: config)
    state = engine.add_player(state: state, message: player_one)
    state = engine.add_player(state: state, message: player_two)

    active_state = described_class.new(clock: -> { now + 31 }, id_generator: id_generator).tick(state: state, config: config)

    expect(active_state["phase"]).to eq("active")
    expect(active_state["terrain"].length).to be >= 12
    expect(active_state["tanks"].map { |tank| tank["login"] }).to eq(%w[one two])
    expect(active_state["players"].map { |player| player["health"] }).to eq([ 100, 100 ])
    expect(active_state["next_fire_at"]).to eq((now + 61).iso8601)
  end

  it "emits volley animation data without persisting transient effects" do
    state = engine.start_setup(state: {}, trigger: starter, config: config, request_id: "req-1")
    state = engine.begin_signup(state: state, previous_scene_name: "Main", config: config)
    state = engine.add_player(state: state, message: player_one)
    state = engine.add_player(state: state, message: player_two)

    active_state = described_class.new(clock: -> { now + 31 }, id_generator: id_generator).tick(state: state, config: config)
    fired_state = described_class.new(clock: -> { now + 61 }, id_generator: id_generator).tick(state: active_state, config: config)

    expect(fired_state["last_volley"]).to include(
      "id" => "round-1",
      "fired_at" => (now + 61).iso8601,
      "expires_at" => (now + 71).iso8601
    )
    expect(fired_state.dig("last_volley", "shots").length).to eq(2)
    expect(fired_state.dig("last_volley", "shots", 0)).to include("shooter" => "one", "weapon" => 1)
    expect(fired_state.dig("last_volley", "shots", 0, "points")).not_to be_empty
    expect(fired_state.dig("last_volley", "shots", 0, "explosions")).not_to be_empty
    expect(fired_state["projectiles"]).to eq([])
    expect(fired_state["explosions"]).to eq([])
  end

  it "clamps aim and weapon choices" do
    state = engine.begin_signup(
      state: engine.start_setup(state: {}, trigger: starter, config: config, request_id: "req-1"),
      previous_scene_name: "Main",
      config: config
    )
    state = engine.add_player(state: state, message: player_one)

    state = engine.update_aim(state: state, message: player_one, angle: 900, power: -4)
    state = engine.update_weapon(state: state, message: player_one, weapon: 3)

    expect(state.dig("players", 0)).to include("angle" => 180.0, "power" => 1.0, "weapon" => 3)
  end
  it "starts a demo round with ten Scorched Earth style NPC tanks" do
    state = engine.start_demo_setup(state: {}, trigger: starter, config: config, request_id: "req-1")
    demo_state = engine.begin_demo(state: state, previous_scene_name: "Main", config: config)

    expect(demo_state).to include("phase" => "active", "demo" => true, "previous_scene_name" => "Main")
    expect(demo_state["players"].length).to eq(10)
    expect(demo_state["tanks"].length).to eq(10)
    expect(demo_state["players"].map { |player| player["display_name"] }.first(4)).to eq(%w[Mussolini Cleopatra Godiva Adolf])
    expect(demo_state["next_fire_at"]).to eq((now + 30).iso8601)
  end
end
