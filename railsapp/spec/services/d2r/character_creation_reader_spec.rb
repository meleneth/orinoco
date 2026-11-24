# frozen_string_literal: true

require "rails_helper"

RSpec.describe D2r::CharacterCreationReader do
  let(:fixture_root) { Rails.root.join("spec/fixtures/files/d2r") }

  it "recognizes the user-confirmed creation fields in training and holdout frames" do
    %w[character_creation_augmented_train.png character_creation_augmented_holdout.png].each do |file|
      expect(described_class.new.call(fixture_root.join(file))).to include(
        "name" => "Augmented",
        "character_class" => "Sorceress",
        "game_version" => "Reign Of The Warlock"
      )
    end
  end

  it "reads the current progression character name from the native text field" do
    %w[progression_character_creation_train.jpg progression_character_creation_holdout.jpg].each do |file|
      expect(described_class.new.call(fixture_root.join(file))).to include(
        "name" => "Redacted",
        "character_class" => "Sorceress",
        "game_version" => "Reign Of The Warlock"
      )
    end
  end
end
