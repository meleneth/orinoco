# frozen_string_literal: true

require "rails_helper"
require "d2r/hud_reader"

RSpec.describe D2r::HudReader do
  it "recognizes area, difficulty, and terror zones from a confirmed holdout frame" do
    reading = described_class.new.call(file_fixture("d2r/hud_cata2_holdout.jpg"))

    expect(reading).to eq(
      "area" => "Catacombs Level 2",
      "difficulty" => "Hell",
      "terror_zones" => [ "Dry Hills", "Halls of the Dead" ]
    )
  end

  it "distinguishes adjacent Catacombs levels and a different terror rotation" do
    reading = described_class.new.call(file_fixture("d2r/hud_cata3_holdout.jpg"))

    expect(reading).to eq(
      "area" => "Catacombs Level 3",
      "difficulty" => "Hell",
      "terror_zones" => [ "Rocky Waste", "Stony Tomb" ]
    )
  end
end
