# frozen_string_literal: true

require "rails_helper"
require "d2r/run_outcome"

RSpec.describe D2r::RunOutcome do
  def observation(type, area = nil)
    { "type" => type, "payload" => { "area" => area } }
  end

  def outcome(*events, **attributes)
    described_class.call(D2rRun.new(**{ run_kind: "countess", events: events }.merge(attributes)))
  end

  let(:floor_five) { observation("d2r.area.changed", "Tower Cellar Level 5") }
  let(:town) { observation("d2r.area.changed", "Rogue Encampment") }
  let(:death) { observation("d2r.player.died") }

  it "completes upon returning to town without ending the game" do
    expect(outcome(floor_five, town)).to eq("completed")
  end

  it "completes upon leaving for a character or game creation menu" do
    %w[d2r.game.ended d2r.character.selection.visible d2r.character.creation.visible d2r.game.creation.visible].each do |type|
      expect(outcome(floor_five, observation(type))).to eq("completed")
    end
  end

  it "does not mistake death followed by town for success" do
    expect(outcome(floor_five, death, town)).to eq("failed")
  end

  it "does not revoke a completed run for a later death" do
    expect(outcome(floor_five, town, death)).to eq("completed")
  end

  it "does not mistake the starting town for a successful return" do
    expect(outcome(town, floor_five)).to eq("in_progress")
  end

  it "distinguishes an incomplete exit" do
    expect(outcome(observation("d2r.area.changed", "Tower Cellar Level 4"), ended_at: Time.current)).to eq("incomplete")
  end

  it "recovers old runs from archived route evidence" do
    expect(outcome(run_evidence: ["Tower Cellar Level 5"], area: "Rogue Encampment")).to eq("completed")
  end
end
