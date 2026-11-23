# frozen_string_literal: true

require "rails_helper"
require "d2r/run_archive"
require "orinoco/pipeline/event"

RSpec.describe D2r::RunArchive do
  let(:archive) { described_class.new }
  let(:game) { { "id" => "detected-game", "started_at" => "2026-11-23T10:00:00Z", "ended_at" => nil } }
  let(:state) { { "game" => game, "level" => 84, "area" => "Tower Cellar Level 5", "difficulty" => "Hell", "terror_zones" => [], "run" => { "kind" => "countess", "started_at" => "2026-11-23T10:00:10Z", "steps" => [] } } }

  def event(type, at, payload = {})
    Orinoco::Pipeline::Event.build(type, payload, occurred_at: "2026-11-23T#{at}Z")
  end

  it "persists detected runs, updates metadata and closes them" do
    archive.call(event("d2r.game.started", "10:00:00", { "game_id" => "detected-game" }), state)
    state["run"]["steps"] = [ { "name" => "tower", "seconds" => 42 } ]
    archive.call(event("d2r.run.step", "10:00:42", { "name" => "tower" }), state)
    game["ended_at"] = "2026-11-23T10:01:00Z"
    archive.call(event("d2r.game.ended", "10:01:00"), state)

    run = D2rRun.find_by!(game_id: "detected-game")
    expect(run.run_kind).to eq("countess")
    expect(run.steps.first.fetch("seconds")).to eq(42)
    expect(run.ended_at).to eq(Time.iso8601("2026-11-23T10:01:00Z"))
    expect(run.events.size).to eq(3)
  end

  it "deduplicates repeated delivery and does not reopen an ended game" do
    started = event("d2r.game.started", "10:00:00", { "game_id" => "detected-game" })
    2.times { archive.call(started, state) }
    expect(D2rRun.count).to eq(1)
    expect(D2rRun.first.events.size).to eq(1)
    game["ended_at"] = "2026-11-23T10:01:00Z"
    archive.call(event("d2r.game.ended", "10:01:00"), state)
    archive.call(started, state)
    expect(D2rRun.first.ended_at).to be_present
  end

  it "builds step timings from detected area changes without manual run selection" do
    state["run"] = nil
    archive.call(event("d2r.game.started", "10:00:00", { "game_id" => "detected-game" }), state)
    state["area"] = "Black Marsh"
    archive.call(event("d2r.area.changed", "10:00:05", { "area" => "Black Marsh" }), state)
    state["area"] = "Forgotten Tower"
    archive.call(event("d2r.area.changed", "10:00:20", { "area" => "Forgotten Tower" }), state)
    game["ended_at"] = "2026-11-23T10:00:30Z"
    archive.call(event("d2r.game.ended", "10:00:30"), state)

    expect(D2rRun.first.steps.map { |step| [ step.fetch("name"), step.fetch("seconds") ] }).to eq([
      [ "Black Marsh", 15.0 ], [ "Forgotten Tower", 10.0 ]
    ])
    expect(D2rRun.first.current_step).to eq({})
  end

  it "archives rune and unique sightings in the inferred game record" do
    state["run"]["confidence"] = 0.9
    state["run"]["evidence"] = [ "Forgotten Tower", "Tower Cellar Level 1" ]
    archive.call(event("d2r.game.started", "10:00:00", { "game_id" => "detected-game" }), state)
    sighting = event("d2r.loot.rune.sighted", "10:00:10", { "name" => "Ist Rune" })
    2.times { archive.call(sighting, state) }
    archive.call(event("d2r.loot.unique.sighted", "10:00:11", { "name" => "Harlequin Crest" }), state)
    run = D2rRun.first
    expect(run.run_confidence).to eq(0.9)
    expect(run.run_evidence).to include("Forgotten Tower")
    expect(run.loot_sightings.map { |loot| loot.fetch("name") }).to eq([ "Ist Rune", "Harlequin Crest" ])
    expect(LootDrop.order(:observed_at).pluck(:kind, :name)).to eq([
      [ "rune", "Ist Rune" ], [ "unique", "Harlequin Crest" ]
    ])
    drop = LootDrop.find_by!(name: "Harlequin Crest")
    expect(drop.d2r_run).to eq(run)
    expect(drop.season.name).to eq("Season 1")
    expect(drop.season.game_definition).to have_attributes(
      name: "Diablo II: Resurrected", publisher: "Blizzard Entertainment",
      year: 2021, link: "https://diablo2.blizzard.com/"
    )
    expect(LootDrop.count).to eq(2)
  end

  it "does not create a record from unconfirmed detector chatter" do
    archive.call(event("d2r.area.changed", "10:00:00", { "area" => "Moo Moo Farm" }), { "game" => nil })
    expect(D2rRun.count).to eq(0)
  end
end
