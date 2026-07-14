# frozen_string_literal: true

require "rails_helper"
require "json"

RSpec.describe Wos::ChatGuessTracker do
  class WosChatGuessTrackerSpecRedis
    attr_reader :values, :lists

    def initialize(values = {})
      @values = values
      @lists = Hash.new { |hash, key| hash[key] = [] }
    end

    def get(key)
      values[key]
    end

    def multi
      yield self
    end

    def rpush(key, value)
      lists[key] << value
    end

    def ltrim(key, start_index, stop_index)
      list = lists[key]
      start_index += list.length if start_index.negative?
      stop_index += list.length if stop_index.negative?
      start_index = [start_index, 0].max
      stop_index = [stop_index, list.length - 1].min
      lists[key] = start_index <= stop_index ? list[start_index..stop_index] : []
    end
  end

  let(:redis) { WosChatGuessTrackerSpecRedis.new(Wos::OverlayStateStore::KEY => JSON.generate(board_state)) }
  let(:clock) { -> { Time.zone.parse("2026-07-13T08:15:00Z") } }
  let(:tracker) { described_class.new(redis: redis, clock: clock) }
  let(:board_state) do
    {
      "recognized_at" => "2026-07-13T08:14:58Z",
      "recognition" => {
        "ruleset" => { "mode" => "base", "hidden_letters" => 0, "fake_letters" => 0 },
        "letters" => [
          { "char" => "S" }, { "char" => "A" }, { "char" => "H" },
          { "char" => "T" }, { "char" => "N" }, { "char" => "K" }
        ],
        "remaining_words" => [
          { "length" => 4, "remaining" => 12 },
          { "length" => 5, "remaining" => 5 }
        ]
      }
    }
  end

  it "records a plausible single-word Twitch guess against the current board" do
    guess = tracker.call(message("thank", name: "mel"))

    expect(guess).to include(
      "state" => "pending",
      "word" => "THANK",
      "player" => "mel",
      "board_recognized_at" => "2026-07-13T08:14:58Z",
      "observed_at" => "2026-07-13T08:15:00.000000Z"
    )
    expect(JSON.parse(redis.lists.fetch(described_class::KEY).first)).to include(
      "word" => "THANK",
      "player" => "mel"
    )
  end

  it "ignores multi-word chat messages" do
    expect(tracker.call(message("thank you"))).to be_nil
    expect(redis.lists[described_class::KEY]).to be_empty
  end

  it "ignores words that do not match any remaining word length" do
    expect(tracker.call(message("thanks"))).to be_nil
    expect(redis.lists[described_class::KEY]).to be_empty
  end

  it "ignores words that cannot be made from visible letters" do
    expect(tracker.call(message("shard"))).to be_nil
    expect(redis.lists[described_class::KEY]).to be_empty
  end

  it "allows missing letters when the active ruleset has hidden letters" do
    board_state.fetch("recognition").fetch("ruleset")["hidden_letters"] = 1

    expect(tracker.call(message("shark"))).to include("word" => "SHARK")
  end

  def message(text, name: "viewer")
    TwitchChatBridge::Message.new(tags: {}, name: name, txt: text)
  end
end
