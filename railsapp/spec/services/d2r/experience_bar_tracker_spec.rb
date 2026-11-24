# frozen_string_literal: true

require "spec_helper"
require "d2r/experience_bar_tracker"

RSpec.describe D2r::ExperienceBarTracker do
  subject(:tracker) { described_class.new }
  let(:character) { { "name" => "Test", "character_class" => "Paladin", "level" => 12 } }

  def observe(fill, seconds)
    tracker.observe(fill, observed_at: format("2026-11-23T12:00:%02dZ", seconds))
  end

  it "increments repeatedly without a character sheet and reconciles the actual level" do
    tracker.seed(character)
    expect(observe(0.98, 0)).to be_empty
    expect(observe(0.02, 1)).to contain_exactly(include(
      "type" => "d2r.level.changed",
      "payload" => include("previous" => 12, "level" => 13, "source" => "xp_bar_rollover")
    ))
    expect(observe(0.03, 2)).to be_empty
    expect(observe(0.95, 3)).to be_empty
    expect(observe(0.01, 4).first.dig("payload", "level")).to eq(14)
    expect(tracker.seed(character.merge("level" => 14))).to be(false)
  end

  it "does not cross invalid samples, long gaps, or character switches" do
    tracker.seed(character)
    observe(0.98, 0)
    observe(nil, 1)
    expect(observe(0.01, 2)).to be_empty
    observe(0.98, 3)
    expect(observe(0.01, 10)).to be_empty
    observe(0.98, 11)
    tracker.seed(character.merge("name" => "Other"))
    expect(observe(0.01, 12)).to be_empty
  end

  it "never invents a level or exceeds 99" do
    observe(1.0, 0)
    expect(observe(0.0, 1)).to be_empty
    tracker.seed(character.merge("level" => 99))
    observe(1.0, 2)
    expect(observe(0.0, 3)).to be_empty
  end
end
