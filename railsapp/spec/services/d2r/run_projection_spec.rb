# frozen_string_literal: true

require "spec_helper"
require "d2r/run_projection"
require "orinoco/pipeline/event"

RSpec.describe D2r::RunProjection do
  class MemoryRedis
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

  let(:projection) { described_class.new(redis: MemoryRedis.new) }

  def emit(type, payload, time)
    projection.call(Orinoco::Pipeline::Event.build(type, payload, occurred_at: "2026-11-22T#{time}Z"))
  end

  it "keeps only five timestamped events while preserving sticky game and character state" do
    emit("d2r.game.started", { "game_id" => "first" }, "10:00:00")
    emit("d2r.level.changed", { "level" => 85 }, "10:00:01")
    5.times { |n| emit("d2r.area.changed", { "area" => "Area #{n}" }, "10:00:0#{n + 2}") }
    state = projection.snapshot

    expect(state["events"].length).to eq(5)
    expect(state["events"].first).to include("message" => "Entered Area 4", "at" => "2026-11-22T10:00:06.000000Z")
    expect(state["level"]).to eq(85)
    expect(state["area"]).to eq("Area 4")
    expect(state.dig("game", "started_at")).to eq("2026-11-22T10:00:00.000000Z")
  end

  it "carries a pre-game selected identity into the next game" do
    emit("d2r.character.selected", {
      "identity_key" => "roster-slot-2",
      "name" => "Hextract",
      "character_class" => "Paladin",
      "level" => 90
    }, "09:59:58")
    state = emit("d2r.game.started", { "game_id" => "selected-game" }, "10:00:00")

    expect(state.fetch("character")).to include(
      "identity_key" => "roster-slot-2", "name" => "Hextract", "level" => 90
    )
    expect(state["level"]).to eq(90)
  end

  it "marks consecutive matching runs and records separate step durations" do
    emit("d2r.game.started", { "game_id" => "one" }, "10:00:00")
    emit("d2r.run.selected", { "kind" => "countess" }, "10:00:01")
    emit("d2r.run.step", { "name" => "waypoint" }, "10:00:02")
    emit("d2r.run.step", { "name" => "tower" }, "10:00:12")
    emit("d2r.game.ended", {}, "10:00:30")
    emit("d2r.game.started", { "game_id" => "two" }, "10:01:00")
    state = emit("d2r.run.selected", { "kind" => "countess" }, "10:01:01")

    expect(state.dig("run", "repeated")).to eq(true)
    expect(state.dig("run", "previous_steps").map { |step| step.fetch("seconds") }).to eq([ 10.0, 18.0 ])
    expect(state.dig("run", "steps")).to be_empty
    state = emit("d2r.run.step", { "name" => "waypoint" }, "10:01:05")
    state = emit("d2r.run.step", { "name" => "tower" }, "10:01:11")
    expect(state.dig("run", "steps", 0, "seconds")).to eq(6.0)
  end

  it "does not mistake a different consecutive run for a repeat" do
    emit("d2r.game.started", { "game_id" => "one" }, "10:00:00")
    emit("d2r.run.selected", { "kind" => "countess" }, "10:00:01")
    emit("d2r.game.started", { "game_id" => "two" }, "10:01:00")
    state = emit("d2r.run.selected", { "kind" => "andy" }, "10:01:01")
    expect(state.dig("run", "repeated")).to eq(false)
  end

  it "renders run and step payloads in visible messages" do
    emit("d2r.game.started", { "game_id" => "one" }, "10:00:00")
    emit("d2r.run.selected", { "kind" => "countess" }, "10:00:01")
    state = emit("d2r.run.step", { "name" => "waypoint" }, "10:00:02")

    expect(state["events"].first(2).map { |event| event.fetch("message") }).to eq([
      "Step: waypoint", "Run: countess"
    ])
  end

  it "projects difficulty and terror zones without spending visible event slots" do
    emit("d2r.difficulty.changed", { "difficulty" => "Hell" }, "10:00:00")
    state = emit("d2r.terror_zones.changed", { "terror_zones" => [ "Dry Hills", "Halls of the Dead" ] }, "10:00:01")

    expect(state["difficulty"]).to eq("Hell")
    expect(state["terror_zones"]).to eq([ "Dry Hills", "Halls of the Dead" ])
    expect(state["events"]).to be_empty
  end

  it "derives live area splits and repeat comparisons from detected areas" do
    emit("d2r.game.started", { "game_id" => "one" }, "10:00:00")
    emit("d2r.area.changed", { "area" => "Black Marsh" }, "10:00:01")
    emit("d2r.area.changed", { "area" => "Forgotten Tower" }, "10:00:11")
    state = emit("d2r.area.changed", { "area" => "Tower Cellar Level 1" }, "10:00:21")
    expect(state.dig("run", "steps").map { |step| [ step["name"], step["seconds"] ] }).to eq([
      [ "Black Marsh", 10.0 ], [ "Forgotten Tower", 10.0 ]
    ])
    emit("d2r.game.ended", {}, "10:00:31")
    emit("d2r.game.started", { "game_id" => "two" }, "10:01:00")
    emit("d2r.area.changed", { "area" => "Black Marsh" }, "10:01:01")
    state = emit("d2r.area.changed", { "area" => "Forgotten Tower" }, "10:01:10")
    expect(state.dig("run", "repeated")).to eq(true)
    expect(state.dig("run", "previous_steps").map { |step| step["seconds"] }).to eq([ 10.0, 10.0, 10.0 ])
  end

  it "infers a Countess run and renders named loot notifications" do
    emit("d2r.game.started", { "game_id" => "one" }, "10:00:00")
    emit("d2r.area.changed", { "area" => "Black Marsh" }, "10:00:01")
    state = emit("d2r.area.changed", { "area" => "Forgotten Tower" }, "10:00:02")
    expect(state.dig("run", "kind")).to eq("countess")
    expect(state.dig("run", "confidence")).to eq(0.75)
    state = emit("d2r.loot.rune.sighted", { "name" => "Ist Rune" }, "10:00:03")
    expect(state.dig("events", 0, "message")).to eq("Rune spotted: Ist Rune")
    state = emit("d2r.loot.unique.sighted", { "name" => "Harlequin Crest" }, "10:00:04")
    expect(state.dig("events", 0, "message")).to eq("Unique spotted: Harlequin Crest")
  end

  it "ignores classifier chatter in the visible feed" do
    state = emit("d2r.state.changed", { "group" => "screen", "current" => "gameplay" }, "10:00:00")
    state = emit("d2r.loading.started", {}, "10:00:01")
    state = emit("d2r.loading.finished", {}, "10:00:02")
    expect(state["events"]).to be_empty
    expect(state["screen"]).to eq("gameplay")
  end
end
