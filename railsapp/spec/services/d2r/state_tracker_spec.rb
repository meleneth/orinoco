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

  it "reports the create-game boundary and arms game lifecycle tracking" do
    tracker = described_class.new
    tracker.observe(classification(screen: "game_creation"))
    events = tracker.observe(classification(screen: "game_creation"))

    expect(events.map { |event| event.fetch("type") }).to include(
      "d2r.state.changed", "d2r.game.creation.visible"
    )
  end

  it "requires three consecutive death frames even at high confidence" do
    tracker = described_class.new

    first = tracker.observe(classification(screen: "death_screen", confidence: 0.99))
    second = tracker.observe(classification(screen: "death_screen", confidence: 0.99))
    expect(first.map { |event| event.fetch("type") }).not_to include("d2r.player.died")
    expect(second.map { |event| event.fetch("type") }).not_to include("d2r.player.died")
    events = tracker.observe(classification(screen: "death_screen", confidence: 0.99))

    expect(events.map { |event| event.fetch("type") }).to include("d2r.player.died")
  end

  it "emits loading finished when gameplay stabilizes after loading" do
    tracker = described_class.new
    tracker.observe(classification(screen: "loading_screen", confidence: 0.99))
    tracker.observe(classification(screen: "gameplay"))
    events = tracker.observe(classification(screen: "gameplay"))

    expect(events.map { |event| event.fetch("type") }).to include("d2r.loading.finished")
  end

  it "starts a game only after character selection, entry loading, and gameplay" do
    tracker = described_class.new
    tracker.observe(classification(screen: "character_select"), observed_at: "2026-11-23T04:00:00Z")
    tracker.observe(classification(screen: "character_select"), observed_at: "2026-11-23T04:00:01Z")
    tracker.observe(classification(screen: "loading_screen"), observed_at: "2026-11-23T04:00:02Z")
    tracker.observe(classification(screen: "gameplay"), observed_at: "2026-11-23T04:00:03Z")
    events = tracker.observe(classification(screen: "gameplay"), observed_at: "2026-11-23T04:00:04Z")

    started = events.find { |event| event.fetch("type") == "d2r.game.started" }
    expect(started.fetch("payload")).to include(
      "game_id" => "visual-2026-11-23T04:00:04Z",
      "boundary" => "character_select_loading_gameplay"
    )
  end

  it "recovers an active game when the observer starts during gameplay" do
    tracker = described_class.new
    tracker.observe(classification(screen: "gameplay"), observed_at: "2026-11-23T04:00:03Z")
    events = tracker.observe(classification(screen: "gameplay"), observed_at: "2026-11-23T04:00:04Z")

    started = events.find { |event| event.fetch("type") == "d2r.game.started" }
    expect(started.fetch("payload")).to include(
      "game_id" => "visual-2026-11-23T04:00:04Z",
      "boundary" => "observer_started_in_game"
    )
  end

  it "does not mistake an in-game loading transition for a new game" do
    tracker = described_class.new
    tracker.observe(classification(screen: "loading_screen"))
    tracker.observe(classification(screen: "gameplay"))
    events = tracker.observe(classification(screen: "gameplay"))

    expect(events.map { |event| event.fetch("type") }).not_to include("d2r.game.started")
  end

  it "ends an observed active game when character selection returns" do
    tracker = described_class.new
    %w[character_select character_select loading_screen gameplay gameplay].each do |screen|
      tracker.observe(classification(screen:))
    end
    tracker.observe(classification(screen: "character_select"))
    events = tracker.observe(classification(screen: "character_select"))

    expect(events.map { |event| event.fetch("type") }).to include("d2r.game.ended")
  end
end
