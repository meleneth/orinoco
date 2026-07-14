# frozen_string_literal: true

class WosOverlayLayerComponent < ApplicationComponent
  def initialize(state: nil)
    @state = state || {}
  end

  private

  attr_reader :state

  def recognition
    state.fetch("recognition", {})
  end

  def screenshot
    state.fetch("screenshot", {})
  end

  def ruleset
    recognition.fetch("ruleset", {})
  end

  def letters
    Array(recognition["letters"]).filter_map { |tile| tile["char"] }.join
  end

  def remaining_words
    Array(recognition["remaining_words"]).select { |entry| entry["remaining"].to_i.positive? }
  end

  def word_rows
    Array(recognition["solved_words"])
  end

  def display_word_rows
    word_rows.reject { |row| row["state"] == "instruction" }.first(8)
  end

  def status_text
    return "Waiting for WOSBrain" if recognition.empty?

    "WOSBrain"
  end

  def updated_at
    state["recognized_at"] || screenshot["captureCompletedAt"]
  end

  def remaining_word_label(entry)
    length = entry["length"].to_i
    remaining = entry["remaining"].to_i
    "#{remaining} x #{length}"
  end

  def row_label(row)
    length = row["word_length"].to_i
    filled = row["filled_count"].to_i
    return row["state"].to_s.humanize if length.zero?

    "#{filled}/#{length}"
  end

  def row_word(row)
    word = row["correct_word"].presence || row["text"].presence
    return word if word.present?

    length = row["word_length"].to_i
    return "-" if length.zero?

    "_" * length
  end

  def row_player(row)
    row["player"].presence || "-"
  end
end