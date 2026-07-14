# frozen_string_literal: true

module Wos
  class Ruleset
    MODES = {
      "base" => {
        hidden_letters: 0,
        fake_letters: 0,
        shows_solved_words: true,
        requires_chat_correlation: false
      },
      "hidden_letter" => {
        hidden_letters: 1,
        fake_letters: 0,
        shows_solved_words: true,
        requires_chat_correlation: false
      },
      "fake_letter" => {
        hidden_letters: 0,
        fake_letters: 1,
        shows_solved_words: true,
        requires_chat_correlation: false
      },
      "hidden_and_fake" => {
        hidden_letters: 1,
        fake_letters: 1,
        shows_solved_words: true,
        requires_chat_correlation: false
      },
      "chat_correlation" => {
        hidden_letters: 1,
        fake_letters: 1,
        shows_solved_words: false,
        requires_chat_correlation: true
      }
    }.freeze

    DEFAULT_MODE = "base"

    attr_reader :mode, :hidden_letters, :fake_letters, :shows_solved_words, :requires_chat_correlation

    def self.for_mode(mode)
      normalized_mode = mode.to_s.strip
      normalized_mode = DEFAULT_MODE if normalized_mode.empty?
      attributes = MODES.fetch(normalized_mode, MODES.fetch(DEFAULT_MODE))
      new(mode: MODES.key?(normalized_mode) ? normalized_mode : DEFAULT_MODE, **attributes)
    end

    def initialize(mode:, hidden_letters:, fake_letters:, shows_solved_words:, requires_chat_correlation:)
      @mode = mode.to_s
      @hidden_letters = hidden_letters.to_i
      @fake_letters = fake_letters.to_i
      @shows_solved_words = !!shows_solved_words
      @requires_chat_correlation = !!requires_chat_correlation
    end

    def to_h
      {
        mode: mode,
        hidden_letters: hidden_letters,
        fake_letters: fake_letters,
        shows_solved_words: shows_solved_words,
        requires_chat_correlation: requires_chat_correlation
      }
    end
  end
end