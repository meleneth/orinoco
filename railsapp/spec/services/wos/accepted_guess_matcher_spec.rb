# frozen_string_literal: true

require "rails_helper"
require "json"

RSpec.describe Wos::AcceptedGuessMatcher do
  class WosAcceptedGuessMatcherSpecRedis
    attr_reader :lists

    def initialize
      @lists = Hash.new { |hash, key| hash[key] = [] }
    end

    def lrange(key, start_index, stop_index)
      list = lists[key]
      start_index += list.length if start_index.negative?
      stop_index += list.length if stop_index.negative?
      start_index = [start_index, 0].max
      stop_index = [stop_index, list.length - 1].min
      start_index <= stop_index ? list[start_index..stop_index] : []
    end

    def multi
      yield self
    end

    def del(key)
      lists.delete(key)
    end

    def rpush(key, value)
      lists[key] << value
    end

    def ltrim(key, start_index, stop_index)
      lists[key] = lrange(key, start_index, stop_index)
    end
  end

  let(:redis) { WosAcceptedGuessMatcherSpecRedis.new }
  let(:matcher) { described_class.new(redis: redis) }
  let(:previous_state) do
    state_at(
      "2026-07-13T08:14:58Z",
      [ { "length" => 4, "remaining" => 12 }, { "length" => 5, "remaining" => 5 } ]
    )
  end
  let(:current_state) do
    state_at(
      "2026-07-13T08:15:02Z",
      [ { "length" => 4, "remaining" => 12 }, { "length" => 5, "remaining" => 4 } ]
    )
  end

  it "accepts a pending guess when the structured remaining count drops for that length" do
    push_guess(word: "THANK", player: "MEL", observed_at: "2026-07-13T08:15:00Z")

    matches = matcher.call(previous_state: previous_state, current_state: current_state)

    expect(matches).to contain_exactly(
      include(
        "state" => "solved",
        "correct_word" => "THANK",
        "player" => "MEL",
        "source" => "twitch_chat",
        "metrics" => include("detection" => "remaining_word_delta")
      )
    )
    expect(stored_guesses.first).to include(
      "state" => "accepted",
      "word" => "THANK",
      "accepted_at" => "2026-07-13T08:15:02Z"
    )
  end

  it "chooses the earliest matching pending guess for each dropped slot" do
    push_guess(word: "SHANK", player: "A", observed_at: "2026-07-13T08:15:01Z")
    push_guess(word: "THANK", player: "B", observed_at: "2026-07-13T08:15:00Z")

    matches = matcher.call(previous_state: previous_state, current_state: current_state)

    expect(matches.map { |match| match.fetch("correct_word") }).to eq(["THANK"])
    expect(stored_guesses.map { |guess| guess.fetch("state") }).to eq(["pending", "accepted"])
  end

  it "does not accept guesses from a different board snapshot" do
    push_guess(word: "THANK", board_recognized_at: "2026-07-13T08:00:00Z")

    expect(matcher.call(previous_state: previous_state, current_state: current_state)).to be_empty
    expect(stored_guesses.first).to include("state" => "pending")
  end

  it "does not accept guesses when no remaining count dropped" do
    push_guess(word: "THANK")

    expect(matcher.call(previous_state: previous_state, current_state: previous_state)).to be_empty
    expect(stored_guesses.first).to include("state" => "pending")
  end

  def state_at(recognized_at, remaining_words)
    {
      "recognized_at" => recognized_at,
      "recognition" => {
        "remaining_words" => remaining_words
      }
    }
  end

  def push_guess(word:, player: "viewer", board_recognized_at: "2026-07-13T08:14:58Z", observed_at: "2026-07-13T08:15:00Z")
    redis.rpush(
      Wos::ChatGuessTracker::KEY,
      JSON.generate(
        "state" => "pending",
        "word" => word,
        "player" => player,
        "raw_text" => word.downcase,
        "board_recognized_at" => board_recognized_at,
        "observed_at" => observed_at
      )
    )
  end

  def stored_guesses
    redis.lrange(Wos::ChatGuessTracker::KEY, 0, -1).map { |raw| JSON.parse(raw) }
  end
end
