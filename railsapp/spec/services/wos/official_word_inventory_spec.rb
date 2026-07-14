# frozen_string_literal: true

require "rails_helper"
require "wos/official_word_inventory"

RSpec.describe Wos::OfficialWordInventory do
  it "counts constructible official words by length and subtracts solved words" do
    %w[
      HANK HANT HAST HATS KHAN ANTS TANK TANS TASK THAN SHAT SHAN
      HANKS KHANS STANK TANKS THANK SHANK THANKS
    ].each do |word|
      OfficialWosWord.create!(word: word, source: "spec")
    end
    OfficialWosWord.create!(word: "AIR", source: "spec")
    OfficialWosWord.create!(word: "STASH", source: "spec")

    result = described_class.new.call(letters: "SAHTNK", solved_words: ["THANK"])

    expect(result.map(&:to_h)).to include(
      { length: 4, total: 12, solved: 0, remaining: 12 },
      { length: 5, total: 6, solved: 1, remaining: 5 }
    )
    expect(result.map(&:length)).not_to include(3)
  end
end