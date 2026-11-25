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

  it "emits a unique label once per area per game before publishing" do
    label = { "kind" => "unique", "name" => "Shako" }
    expect(tracker.observe([label], observed_at: "1", area: "Catacombs Level 2")).to be_empty
    expect(tracker.observe([label], observed_at: "2").size).to eq(1)

    tracker.observe([], observed_at: "3")
    2.times do
      expect(tracker.observe([label.merge("name" => "SHAKO")], observed_at: "4")).to be_empty
    end

    expect(tracker.observe([label], observed_at: "5", area: "Catacombs Level 3")).to be_empty
    expect(tracker.observe([label], observed_at: "6").size).to eq(1)
    expect(tracker.observe([label], observed_at: "7", area: "Catacombs Level 2")).to be_empty
    expect(tracker.observe([label], observed_at: "8")).to be_empty

    expect(tracker.observe([label], observed_at: "9", area: "Catacombs Level 2", new_game: true)).to be_empty
    expect(tracker.observe([label], observed_at: "10").size).to eq(1)
  end

  it "rejects unrecognized rune names" do
    labels = [ { "kind" => "rune", "name" => "Super Rune" } ]
    2.times { expect(tracker.observe(labels, observed_at: "time")).to eq([]) }
  end
end
