# frozen_string_literal: true

require "spec_helper"
require "d2r/hud_area_reader"

RSpec.describe D2r::HudAreaReader do
  it "parses the Countess route from recognized HUD text" do
    expect(described_class.parse("Difficulty: Hell\nBlack Marsh")).to eq("Black Marsh")
    expect(described_class.parse("Forgotten Tower")).to eq("Forgotten Tower")
    expect(described_class.parse("Tower Cellar Level 5")).to eq("Tower Cellar Level 5")
  end

  it "does not manufacture an area from unrecognized text" do
    expect(described_class.parse("some unmatched hud fragments")).to be_nil
  end
end
