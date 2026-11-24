# frozen_string_literal: true

require "rails_helper"

RSpec.describe D2r::CharacterMenuReader do
  let(:fixture_root) { Rails.root.join("spec/fixtures/files/d2r") }

  {
    "character_select" => %w[progression_character_select_train.jpg progression_character_select_holdout.jpg],
    "game_creation" => %w[progression_game_creation_train.jpg progression_game_creation_holdout.jpg]
  }.each do |screen, files|
    it "reads the selected identity from #{screen.tr('_', ' ')} fixtures" do
      files.each do |file|
        expect(described_class.new.call(fixture_root.join(file), screen:)).to eq(
          "name" => "REDACTED", "character_class" => "Sorceress", "level" => 1
        )
      end
    end
  end

  it "does not apply a menu crop to an unsupported screen" do
    expect(described_class.new.call(fixture_root.join("progression_gameplay_holdout.jpg"), screen: "gameplay")).to eq({})
  end
end
