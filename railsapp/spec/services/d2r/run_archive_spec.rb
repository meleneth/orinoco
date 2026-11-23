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

  it "does not create a record from unconfirmed detector chatter" do
    archive.call(event("d2r.area.changed", "10:00:00", { "area" => "Moo Moo Farm" }), { "game" => nil })
    expect(D2rRun.count).to eq(0)
  end
end
