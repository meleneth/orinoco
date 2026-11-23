# frozen_string_literal: true

require "spec_helper"
require "d2r/loot_tracker"

RSpec.describe D2r::LootTracker do
  let(:tracker) { described_class.new }

  it "requires consecutive sightings and emits each visible item once" do
    labels = [ { "kind" => "rune", "name" => "Ist Rune" } ]
    expect(tracker.observe(labels, observed_at: "first")).to eq([])
    changes = tracker.observe(labels, observed_at: "second")
    expect(changes).to include(include("type" => "d2r.loot.rune.sighted",
      "payload" => include("name" => "Ist Rune")))
    expect(tracker.observe(labels, observed_at: "third")).to eq([])
    tracker.observe([], observed_at: "fourth")
    expect(tracker.observe(labels, observed_at: "fifth")).to eq([])
    expect(tracker.observe(labels, observed_at: "sixth").length).to eq(1)
  end

  it "records unique-name candidates without declaring ownership" do
    labels = [ { "kind" => "unique", "name" => "Harlequin Crest" } ]
    tracker.observe(labels, observed_at: "first")
    changes = tracker.observe(labels, observed_at: "second")
    expect(changes.first).to include("type" => "d2r.loot.unique.sighted")
    expect(changes.first.fetch("payload")).to include("name" => "Harlequin Crest",
      "source" => "ground_label")
  end

  it "rejects unrecognized rune names" do
    labels = [ { "kind" => "rune", "name" => "Super Rune" } ]
    2.times { expect(tracker.observe(labels, observed_at: "time")).to eq([]) }
  end
end
