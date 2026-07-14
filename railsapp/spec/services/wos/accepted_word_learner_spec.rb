# frozen_string_literal: true

require "rails_helper"
require "wos/accepted_word_learner"

RSpec.describe Wos::AcceptedWordLearner do
  it "learns accepted solved words into the official WOS word table" do
    learner = described_class.new(clock: -> { Time.zone.parse("2026-07-13T08:00:00Z") })

    learner.call(
      recognition: {
        "solved_words" => [
          { "state" => "solved", "correct_word" => " thank " },
          { "state" => "blank", "correct_word" => nil },
          { "state" => "solved", "text" => "mute" },
          { "state" => "solved", "correct_word" => "THANK" }
        ]
      },
      observed_at: "2026-07-13T09:00:00Z"
    )

    expect(OfficialWosWord.order(:word).pluck(:word, :length, :source)).to eq([
      ["MUTE", 4, "wos_screen"],
      ["THANK", 5, "wos_screen"]
    ])
    thank = OfficialWosWord.find_by!(word: "THANK")
    expect(thank.metadata).to include(
      "first_seen_at" => "2026-07-13T09:00:00.000000Z",
      "last_seen_at" => "2026-07-13T09:00:00.000000Z",
      "seen_count" => 1
    )
  end

  it "updates last seen metadata without replacing the original source" do
    word = OfficialWosWord.create!(
      word: "MUTE",
      source: "seed",
      metadata: { "first_seen_at" => "2026-07-13T08:00:00.000000Z", "seen_count" => 2 }
    )

    described_class.new.call(
      recognition: { "solved_words" => [ { "correct_word" => "mute" } ] },
      observed_at: "2026-07-13T09:00:00Z"
    )

    word.reload
    expect(word.source).to eq("seed")
    expect(word.metadata).to include(
      "first_seen_at" => "2026-07-13T08:00:00.000000Z",
      "last_seen_at" => "2026-07-13T09:00:00.000000Z",
      "seen_count" => 3
    )
  end
end