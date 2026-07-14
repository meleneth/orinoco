# frozen_string_literal: true

require "json"

module Wos
  class ChatGuessTracker
    KEY = "wos:chat:guesses"
    LIMIT = 250

    def initialize(redis:, overlay_state_store: Wos::OverlayStateStore.new(redis: redis), clock: -> { Time.current })
      @redis = redis
      @overlay_state_store = overlay_state_store
      @clock = clock
    end

    def call(message)
      state = overlay_state_store.read
      recognition = state.fetch("recognition", {})
      word = normalized_single_word(message.txt)
      return nil unless word
      return nil unless plausible_guess?(word, recognition)

      guess = {
        "state" => "pending",
        "word" => word,
        "player" => message.display_name.to_s,
        "raw_text" => message.txt.to_s,
        "board_recognized_at" => state["recognized_at"].to_s,
        "observed_at" => clock.call.iso8601(6)
      }
      persist_guess(guess)
      guess
    end

    private

    attr_reader :redis, :overlay_state_store, :clock

    def normalized_single_word(text)
      tokens = text.to_s.scan(/[A-Za-z]+/)
      return nil unless tokens.length == 1

      word = tokens.first.upcase
      word.length >= 2 ? word : nil
    end

    def plausible_guess?(word, recognition)
      letters = visible_letters(recognition)
      return false if letters.empty?
      return false unless remaining_lengths(recognition).include?(word.length)

      missing_letter_count(word, letters) <= ruleset_value(recognition, "hidden_letters")
    end

    def visible_letters(recognition)
      Array(recognition["letters"]).filter_map { |tile| tile["char"].to_s.upcase[/[A-Z]/] }
    end

    def remaining_lengths(recognition)
      Array(recognition["remaining_words"]).filter_map do |entry|
        next unless entry["remaining"].to_i.positive?

        length = entry["length"].to_i
        length.positive? ? length : nil
      end.uniq
    end

    def ruleset_value(recognition, key)
      recognition.fetch("ruleset", {}).fetch(key, 0).to_i
    end

    def missing_letter_count(word, letters)
      available = letter_counts(letters)
      letter_counts(word.chars).sum do |char, needed|
        [needed - available.fetch(char, 0), 0].max
      end
    end

    def letter_counts(chars)
      chars.each_with_object(Hash.new(0)) { |char, counts| counts[char] += 1 }
    end

    def persist_guess(guess)
      redis.multi do |tx|
        tx.rpush(KEY, JSON.generate(guess))
        tx.ltrim(KEY, -LIMIT, -1)
      end
    end
  end
end
