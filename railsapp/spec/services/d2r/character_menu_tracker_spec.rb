# frozen_string_literal: true

require "rails_helper"

RSpec.describe D2r::CharacterMenuTracker do
  let(:reading) { { "name" => "REDACTED", "character_class" => "Sorceress", "level" => 1 } }

  it "confirms selected and draft identities independently" do
    tracker = described_class.new

    expect(tracker.observe_creation(reading)).to be_empty
    expect(tracker.observe_creation(reading).sole.fetch("type")).to eq("d2r.character.creation.draft_observed")
    expect(tracker.observe_selected(reading)).to be_empty
    expect(tracker.observe_selected(reading).sole).to eq(
      "type" => "d2r.character.selected", "payload" => reading
    )
  end

  it "does not confirm incomplete identities" do
    tracker = described_class.new(confirmations: 1)

    expect(tracker.observe_selected("level" => 1)).to be_empty
  end
end
