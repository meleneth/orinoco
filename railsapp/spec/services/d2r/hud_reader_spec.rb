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

  it "reads a Normal terror rotation with no modifier, including the first zone and Pit" do
    hud = Vips::Image.new_from_file(file_fixture("d2r/hud/hud_tamoe_highland_normal.png").to_s)
    frame = hud.embed(1520, 0, 1920, 1200)

    Tempfile.create([ "d2r-normal-terror", ".jpg" ]) do |file|
      frame.jpegsave(file.path, Q: 70)

      expect(described_class.new.call(file.path).fetch("terror_zones")).to eq(
        [ "Tamoe Highland", "Pit", "Monastery Gate", "Outer Cloister" ]
      )
    end
  end
end
