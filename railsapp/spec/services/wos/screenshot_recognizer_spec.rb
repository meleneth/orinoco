# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "wos/screenshot_recognizer"

RSpec.describe Wos::ScreenshotRecognizer do
  def sorted_letters(value)
    value.chars.sort.join
  end
  let(:fixtures_dir) { File.expand_path("../../fixtures/files/wos", __dir__) }
  let(:fixture_expectations) do
    {
      "letters_utelazq.png" => "UTELAZQ",
      "letters_altezqu.png" => "ALTEZQU",
      "letters_rziadl.png" => "RZIADL",
      "letters_airleze.png" => "AIRLEZE",
      "letters_sahtnk_answer_thank.png" => "SAHTNK",
      "letters_oerbxs.png" => "OERBXS"
    }
  end

  let(:wos_fixture_paths) do
    fixture_expectations.keys.map { |name| File.join(fixtures_dir, name) }
  end

  let(:unlabeled_live_fixture_names) do
    [
      "candidate_acimrrah_answer_march.png",
      "candidate_borexs.png"
    ]
  end

  let(:live_anagram_expectations) do
    {
      "anagram_defense.png" => "DEFENSE",
      "anagram_diffuse.png" => "DIFFUSE",
      "anagram_feast.png" => "FEAST",
      "anagram_further.png" => "FURTHER"
    }
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
    result = described_class.call(File.join(fixtures_dir, "letters_airleze.png"))

    expect(result.solved_word_regions.length).to eq(4)
    expect(result.solved_word_regions.map(&:state)).to all(eq("blank"))
    expect(result.solved_word_regions.map(&:word_length)).to all(eq(7))
    expect(result.solved_word_regions.map(&:filled_count)).to all(eq(0))
  end
  it "recognizes live board character multisets without assuming tile order" do
    live_anagram_expectations.each do |fixture, expected_letters|
      result = described_class.call(File.join(fixtures_dir, fixture))
      visible_letters = result.letter_tiles.filter_map(&:char).join

      expect(result.letter_tiles.length).to eq(expected_letters.length)
      expect(sorted_letters(visible_letters)).to eq(sorted_letters(expected_letters))
    end
  end
  it "keeps unlabeled live board captures in the corpus without assuming tile order" do
    unlabeled_live_fixture_names.each do |fixture|
      result = described_class.call(File.join(fixtures_dir, fixture))

      expect(result.letter_tiles.length).to be_between(5, 7).inclusive
      expect(result.letter_tiles.map(&:state)).to all(eq("visible"))
      expect(result.remaining_words.map(&:to_h)).to all(satisfy { |row| row.fetch(:source).to_s.start_with?("screen_blank_") })
    end
  end

  it "documents the live FEAST remaining-word count target" do
    result = described_class.call(File.join(fixtures_dir, "anagram_feast.png"))

    pending("remaining-word segmenter currently merges adjacent blank slots on this capture")
    expect(result.remaining_words.map(&:to_h)).to include(hash_including(length: 5, total: 4, remaining: 4))
    expect(result.remaining_words.map(&:to_h)).to include(hash_including(length: 4))
  end
  it "serializes accepted words separately from blank word-bank evidence" do
    result = described_class.call(File.join(fixtures_dir, "letters_sahtnk_answer_thank.png"))
    payload = result.to_h

    expect(payload.fetch(:solved_words).map { |row| row.fetch(:state) }).to all(eq("solved"))
    expect(payload.fetch(:solved_words).map { |row| row.fetch(:correct_word) }).to include("THANK")
    expect(payload.fetch(:blank_word_banks).map { |row| row.fetch(:state) }).to all(eq("blank"))
    expect(payload.fetch(:remaining_words)).to include(hash_including(length: 4, remaining: 12))
  end
  it "documents the live MARCH solved-word target" do
    result = described_class.call(File.join(fixtures_dir, "candidate_acimrrah_answer_march.png"))

    pending("solved-word recognizer currently reads the player label instead of the accepted word")
    expect(result.solved_word_regions.map(&:correct_word)).to include("MARCH")
  end
  it "extracts accepted words and player labels from answer-heavy fixtures" do
    expectations = {
      "letters_sahtnk_answer_thank.png" => { word: "THANK", player: "MEL" },
      "candidate_tiuenn_answer_mute.png" => { word: "MUTE", player: "MEL" },
      "candidate_olosasi_answer_classic.png" => { word: "CLASSIC", player: "MEL" }
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
