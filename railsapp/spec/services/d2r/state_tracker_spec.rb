# frozen_string_literal: true

require "spec_helper"
require "d2r/state_tracker"

RSpec.describe D2r::StateTracker do
  def classification(screen:, confidence: 0.95)
    {
      "signals" => {
        "screen" => { "state" => screen, "confidence" => confidence },
        "left_panel" => { "state" => "none", "confidence" => 0.9 }
      }
    }
  end

  it "debounces ordinary state changes and does not repeat stable events" do
    tracker = described_class.new

    expect(tracker.observe(classification(screen: "gameplay"))).to be_empty
    events = tracker.observe(classification(screen: "boss_visible"))
    expect(events.map { |event| event.fetch("type") }).not_to include("d2r.boss.engaged")
    events = tracker.observe(classification(screen: "boss_visible"))
    expect(events.map { |event| event.fetch("type") }).to include("d2r.state.changed", "d2r.boss.engaged")
    expect(tracker.observe(classification(screen: "boss_visible"))).to be_empty
  end

  it "reports confirmed character selection and creation separately" do
    tracker = described_class.new
    tracker.observe(classification(screen: "character_select"))
    events = tracker.observe(classification(screen: "character_select"))
    expect(events.map { |event| event.fetch("type") }).to include("d2r.character.selection.visible")

    tracker.observe(classification(screen: "character_creation"))
    events = tracker.observe(classification(screen: "character_creation"))
    expect(events.map { |event| event.fetch("type") }).to include("d2r.character.creation.visible")
    expect(tracker.observe(classification(screen: "character_creation"))).to be_empty
  end

  it "emits high-confidence death immediately" do
    events = described_class.new.observe(classification(screen: "death_screen", confidence: 0.99))

    expect(events.map { |event| event.fetch("type") }).to include("d2r.player.died")
  end

  it "emits loading finished when gameplay stabilizes after loading" do
    tracker = described_class.new
    tracker.observe(classification(screen: "loading_screen", confidence: 0.99))
    tracker.observe(classification(screen: "gameplay"))
    events = tracker.observe(classification(screen: "gameplay"))

    expect(events.map { |event| event.fetch("type") }).to include("d2r.loading.finished")
  end
end
