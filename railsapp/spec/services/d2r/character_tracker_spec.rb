# frozen_string_literal: true

require "spec_helper"
require "d2r/character_tracker"

RSpec.describe D2r::CharacterTracker do
  let(:tracker) { described_class.new }
  let(:identity) { { "name" => "Hextract", "character_class" => "Paladin" } }

  it "confirms fields independently and retains known values across OCR failures" do
    first = identity.merge("level" => 10, "experience" => 100, "stats" => { "strength" => 25 })
    expect(tracker.observe(first)).to be_empty
    events = tracker.observe(first)
    expect(events.map { |event| event.fetch("type") }).to include(
      "d2r.character.observed", "d2r.level.changed", "d2r.experience.changed"
    )

    expect(tracker.observe(identity.merge("experience" => 110))).to be_empty
    events = tracker.observe(identity.merge("experience" => 110))
    observation = events.find { |event| event.fetch("type") == "d2r.character.observed" }
    expect(observation.fetch("payload")).to include("level" => 10, "experience" => 110)
    expect(observation.dig("payload", "stats", "strength")).to eq(25)
    expect(events.find { |event| event.fetch("type") == "d2r.experience.changed" }.fetch("payload")).to include(
      "previous" => 100, "delta" => 10
    )
  end

  it "accepts a stable attribute while experience keeps changing" do
    tracker.observe(identity.merge("experience" => 100, "stats" => { "vitality" => 30 }))
    events = tracker.observe(identity.merge("experience" => 101, "stats" => { "vitality" => 30 }))

    observation = events.find { |event| event.fetch("type") == "d2r.character.observed" }
    expect(observation.dig("payload", "stats", "vitality")).to eq(30)
    expect(observation.fetch("payload")).not_to have_key("experience")
  end
end
