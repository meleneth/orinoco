# frozen_string_literal: true

require "rails_helper"

RSpec.describe OfficialWosWord, type: :model do
  it "normalizes words and records their length" do
    word = described_class.create!(word: " lizard ", source: "spec")

    expect(word.word).to eq("LIZARD")
    expect(word.length).to eq(6)
    expect(described_class.with_length(6)).to include(word)
  end

  it "requires unique uppercase alphabetic words" do
    described_class.create!(word: "RZIADL")

    duplicate = described_class.new(word: "rziadl")
    expect(duplicate).not_to be_valid
    expect(described_class.new(word: "BAD1")).not_to be_valid
  end
end