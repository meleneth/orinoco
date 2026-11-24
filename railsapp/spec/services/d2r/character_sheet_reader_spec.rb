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

  it "normalizes D2R glyph substitutions in identity and compact experience text" do
    text = "REDACTED\n| LeveL | S@RCERESS @ oF 500\n"

    expect(described_class.parse_identity(text)).to eq(
      "name" => "REDACTED", "level" => 1, "character_class" => "Sorceress"
    )
    expect(described_class.parse_experience(text)).to eq(
      "experience" => 0, "experience_next_level" => 500
    )
  end

  it "reads identity, experience, and stats independently from a progression fixture" do
    path = Pathname(__dir__).join("../../fixtures/files/d2r/progression_character_sheet_holdout.jpg").expand_path

    expect(described_class.new.call(path)).to include(
      "name" => "REDACTED",
      "character_class" => "Sorceress",
      "level" => 1,
      "experience" => 0,
      "experience_next_level" => 500,
      "stats" => include("strength" => 10, "mana" => 35, "fire_resistance" => 0)
    )
  end
end
