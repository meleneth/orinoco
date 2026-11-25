# frozen_string_literal: true

require "spec_helper"
require "d2r/hud_area_reader"

RSpec.describe D2r::HudAreaReader do
  it "parses the Countess route from recognized HUD text" do
    expect(described_class.parse("Black Marsh\nDifficulty: Hell")).to eq("Black Marsh")
    expect(described_class.parse("Forgotten Tower")).to eq("Forgotten Tower")
    expect(described_class.parse("Tower Cellar Level 5")).to eq("Tower Cellar Level 5")
  end

  it "tolerates bounded D2R-font OCR substitutions" do
    text = <<~TEXT
      Te@wer CELLAR LEVEL 5
      DIFFICULTY: HELL
      THR@®NE @F DESTRUCTION
    TEXT

    expect(described_class.parse(text)).to eq("Tower Cellar Level 5")
    expect(described_class.parse("TewerR CELLAR LEVEL 5")).to eq("Tower Cellar Level 5")
    expect(described_class.parse("GAME: STARTINGAGAIN\nBLe@eo Meer")).to eq("Blood Moor")
  end

  it "reads an area below the game-name line from a Normal-game capture" do
    fixture = Pathname(__dir__).join("../../fixtures/files/d2r/gameplay_blood_moor_normal_holdout.jpg").expand_path
    reading = described_class.new.call(fixture)

    expect(reading).to eq("area" => "Blood Moor", "game_named" => true)
  end

  it "recognizes a game name and explicit difficulty without resolving the area" do
    expect(described_class.read_hud("Game: Example\nUnreadable area\nDifficucty: Nightmare")).to eq(
      "game_named" => true, "difficulty" => "Nightmare"
    )
  end

  it "does not confuse a listed terror zone for the current area" do
    expect(described_class.parse("unknown heading\nTHRONE OF DESTRUCTION")).to be_nil
  end

  it "does not manufacture an area from unrecognized text" do
    expect(described_class.parse("some unmatched hud fragments")).to be_nil
  end
end
