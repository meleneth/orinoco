# frozen_string_literal: true

require "spec_helper"
require "d2r/character_sheet_reader"

RSpec.describe D2r::CharacterSheetReader do
  it "parses identity and level from their normalized field text" do
    expect(described_class.parse_identity("Hextract\nLevel 90 Paladin\n")).to eq(
      "name" => "Hextract", "level" => 90, "character_class" => "Paladin"
    )
  end

  it "parses current and next-level experience independently" do
    expect(described_class.parse_experience("Current Experience 1,234,567\nNext Level 2,000,000")).to eq(
      "experience" => 1_234_567, "experience_next_level" => 2_000_000
    )
  end

  it "does not invent values when a field is unreadable" do
    expect(described_class.parse_named_numbers("Strength ???", %w[strength vitality])).to be_empty
  end
end
