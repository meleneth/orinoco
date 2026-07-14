# frozen_string_literal: true

require "json"
require_relative "chat_guess_tracker"

module Wos
  class AcceptedGuessMatcher
    SOURCE = "twitch_chat"

    def initialize(redis:, guess_key: Wos::ChatGuessTracker::KEY)
      @redis = redis
      @guess_key = guess_key
    end

    def call(previous_state:, current_state:)
      remaining_drops = remaining_drops(previous_state: previous_state, current_state: current_state)
      return [] if remaining_drops.empty?

      guesses = read_guesses
      matches = match_guesses(
        guesses: guesses,
        remaining_drops: remaining_drops,
        board_recognized_at: previous_state["recognized_at"].to_s,
        accepted_at: current_state["recognized_at"].to_s
      )
      rewrite_guesses(guesses) if matches.any?
      matches.map { |guess| solved_word_for(guess) }
    end

    private

    attr_reader :redis, :guess_key

    def remaining_drops(previous_state:, current_state:)
      previous = remaining_by_length(previous_state)
      current = remaining_by_length(current_state)

      previous.each_with_object({}) do |(length, previous_remaining), drops|
        drop = previous_remaining - current.fetch(length, previous_remaining)
        drops[length] = drop if drop.positive?
      end
    end

    def remaining_by_length(state)
      Array(state.dig("recognition", "remaining_words")).each_with_object({}) do |entry, result|
        length = entry["length"].to_i
        next unless length.positive?

        result[length] = entry["remaining"].to_i
      end
    end

    def read_guesses
      Array(redis.lrange(guess_key, 0, -1)).filter_map do |raw|
        parsed = JSON.parse(raw)
        parsed if parsed.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
    end

    def match_guesses(guesses:, remaining_drops:, board_recognized_at:, accepted_at:)
      matches = []

      remaining_drops.each do |length, count|
        guesses.select { |guess| pending_match?(guess: guess, length: length, board_recognized_at: board_recognized_at) }
          .sort_by { |guess| guess["observed_at"].to_s }
          .first(count)
          .each do |guess|
            guess["state"] = "accepted"
            guess["accepted_at"] = accepted_at
            matches << guess
          end
      end

      matches
    end

    def pending_match?(guess:, length:, board_recognized_at:)
      guess["state"].to_s == "pending" &&
        guess["board_recognized_at"].to_s == board_recognized_at &&
        guess["word"].to_s.length == length
    end

    def rewrite_guesses(guesses)
      redis.multi do |tx|
        tx.del(guess_key)
        guesses.each { |guess| tx.rpush(guess_key, JSON.generate(guess)) }
        tx.ltrim(guess_key, -Wos::ChatGuessTracker::LIMIT, -1)
      end
    end

    def solved_word_for(guess)
      {
        "state" => "solved",
        "correct_word" => guess.fetch("word"),
        "text" => guess.fetch("word"),
        "player" => guess["player"].to_s,
        "word_length" => guess.fetch("word").length,
        "filled_count" => guess.fetch("word").length,
        "confidence" => 1.0,
        "source" => SOURCE,
        "raw_text" => guess["raw_text"].to_s,
        "metrics" => {
          "detection" => "remaining_word_delta",
          "board_recognized_at" => guess["board_recognized_at"].to_s,
          "observed_at" => guess["observed_at"].to_s,
          "accepted_at" => guess["accepted_at"].to_s
        }
      }
    end
  end
end
