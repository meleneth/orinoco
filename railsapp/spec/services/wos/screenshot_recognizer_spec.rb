# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "wos/screenshot_recognizer"

RSpec.describe Wos::ScreenshotRecognizer do
  let(:fixtures_dir) { File.expand_path("../../fixtures/files/wos", __dir__) }
  let(:fixture_expectations) do
    {
      "example_wos_1.png" => "UTELAZQ",
      "example_wos_2.png" => "ALTEZQU",
      "live_lizard.png" => "RZIADL",
      "live_latest_20260713_125054.png" => "AIRLEZE",
      "live_latest_20260713_130753.png" => "SAHTNK",
      "wos_live_latest_20260713_143201.png" => "OERBXS"
    }
  end

  let(:wos_fixture_paths) do
    fixture_expectations.keys.map { |name| File.join(fixtures_dir, name) }
  end

  it "returns a structured WOS recognition result for the starter screenshots" do
    wos_fixture_paths.each do |path|
      result = described_class.call(path)

      expect(result.image).to include(
        width: a_kind_of(Integer),
        height: a_kind_of(Integer),
        bands: 4
      )
      expect(result.regions.keys).to include(:game, :letter_board, :solved_words)
      expected_letters = fixture_expectations.fetch(File.basename(path))
      expect(result.letter_tiles.length).to eq(expected_letters.length)
      visible_tiles = result.letter_tiles.select { |tile| tile.state == "visible" }
      expect(visible_tiles.length).to eq(expected_letters.length)
      expect(visible_tiles.map(&:char).join).to eq(expected_letters)
      expect(visible_tiles).to all(satisfy { |tile| tile.metrics.dig(:letter_guess, :candidates).is_a?(Array) })
      expect(result.solved_word_regions.length).to be >= 0
      expect(result.small_text_regions.length).to be > 0
      expect(result.small_text_regions.map(&:source_region)).to include(:solved_words)
      expect(result.ruleset.to_h).to include(
        mode: "base",
        hidden_letters: 0,
        fake_letters: 0,
        shows_solved_words: true,
        requires_chat_correlation: false
      )

      payload = result.to_h
      expect(payload.fetch(:ruleset)).to include(
        mode: "base",
        hidden_letters: 0,
        fake_letters: 0
      )
      expect(payload.fetch(:letters).first).to include(
        index: 0,
        state: a_kind_of(String),
        char: satisfy { |value| value.nil? || value.match?(/\A[A-Z]\z/) },
        confidence: a_kind_of(Float)
      )
      expect(payload.fetch(:small_text).first).to include(
        index: 0,
        source_region: a_kind_of(Symbol),
        state: "visible_unread",
        text: nil,
        player: nil
      )
      if payload.fetch(:solved_words).any?
        expect(payload.fetch(:solved_words).first).to include(
          index: 0,
          state: a_kind_of(String),
          word_length: a_kind_of(Integer),
          filled_count: a_kind_of(Integer),
          raw_text: a_kind_of(String)
        )
      end
    end
  end

  it "recognizes visible blank word slots in the latest live fixture" do
    result = described_class.call(File.join(fixtures_dir, "live_latest_20260713_125054.png"))

    expect(result.solved_word_regions.length).to eq(4)
    expect(result.solved_word_regions.map(&:state)).to all(eq("blank"))
    expect(result.solved_word_regions.map(&:word_length)).to all(eq(7))
    expect(result.solved_word_regions.map(&:filled_count)).to all(eq(0))
  end
  it "extracts accepted words and player labels from answer-heavy fixtures" do
    expectations = {
      "live_latest_20260713_130753.png" => { word: "THANK", player: "MEL" },
      "wos_live_latest_20260713_135505.png" => { word: "MUTE", player: "MEL" }
    }

    expectations.each do |fixture, expected|
      result = described_class.call(File.join(fixtures_dir, fixture))
      solved_rows = result.solved_word_regions.select { |row| row.state == "solved" }

      expect(solved_rows.map(&:correct_word)).to include(expected.fetch(:word))
      row = solved_rows.find { |entry| entry.correct_word == expected.fetch(:word) }
      expect(row.player).to eq(expected.fetch(:player))
      expect(row.filled_count).to eq(expected.fetch(:word).length)
    end
  end
  it "exports calibrated debug crops and recognition metadata" do
    Dir.mktmpdir("wos-recognizer") do |dir|
      result = described_class.call(wos_fixture_paths.first, debug_dir: dir)

      expect(result).to be_a(Wos::RecognitionResult)
      expect(File).to exist(File.join(dir, "letter_board.png"))
      expect(File).to exist(File.join(dir, "solved_words.png"))
      expect(File).to exist(File.join(dir, "recognition.json"))
      expect(Dir[File.join(dir, "letter_tiles", "*.png")].length).to eq(7)
      expect(Dir[File.join(dir, "small_text", "*.png")].length).to be > 0
    end
  end
end
