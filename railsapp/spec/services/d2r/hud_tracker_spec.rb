# frozen_string_literal: true

require "spec_helper"
require "d2r/hud_tracker"

RSpec.describe D2r::HudTracker do
  it "publishes each stable HUD field once and emits subsequent changes" do
    tracker = described_class.new(confirmations: 2)
    first = { "area" => "Catacombs Level 2", "difficulty" => "Hell", "terror_zones" => [ "Dry Hills" ] }

    expect(tracker.observe(first, observed_at: "one")).to be_empty
    events = tracker.observe(first, observed_at: "two")
    expect(events.map { |event| event.fetch("type") }).to eq(%w[
      d2r.area.changed d2r.difficulty.changed d2r.terror_zones.changed
    ])
    expect(tracker.observe(first, observed_at: "three")).to be_empty

    changed = first.merge("area" => "Catacombs Level 3")
    expect(tracker.observe(changed, observed_at: "four")).to be_empty
    expect(tracker.observe(changed, observed_at: "five").sole).to include(
      "type" => "d2r.area.changed",
      "payload" => include("area" => "Catacombs Level 3", "previous" => "Catacombs Level 2")
    )
  end

  it "confirms the same difficulty again when a new game starts" do
    tracker = described_class.new
    reading = { "difficulty" => "Normal" }
    tracker.observe(reading, observed_at: "one")
    expect(tracker.observe(reading, observed_at: "two").size).to eq(1)

    tracker.reset_difficulty

    expect(tracker.observe(reading, observed_at: "three")).to be_empty
    expect(tracker.observe(reading, observed_at: "four").sole).to include(
      "type" => "d2r.difficulty.changed", "payload" => include("difficulty" => "Normal")
    )
  end
end
