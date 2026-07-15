# frozen_string_literal: true

require "rails_helper"
require "orinoco/pipeline/event"

RSpec.describe WosProjection::Handler do
  class WosProjectionSpecRedis
    attr_reader :values

    def initialize
      @values = {}
    end

    def set(key, value)
      @values[key] = value
    end

    def get(key)
      @values[key]
    end
  end

  let(:redis) { WosProjectionSpecRedis.new }
  let(:broadcaster) { class_double(Turbo::StreamsChannel).as_stubbed_const }
  let(:accepted_word_learner) { instance_double(Wos::AcceptedWordLearner, call: nil) }
  let(:accepted_guess_matcher) { instance_double(Wos::AcceptedGuessMatcher, call: []) }
  let(:status_store) do
    instance_double(
      Wos::StatusStore,
      projection_succeeded!: nil,
      no_active_board!: nil,
      projection_failed!: nil
    )
  end
  let(:handler) do
    described_class.new(
      redis: redis,
      broadcaster: broadcaster,
      accepted_word_learner: accepted_word_learner,
      accepted_guess_matcher: accepted_guess_matcher,
      status_store: status_store
    )
  end
  let(:event) do
    Orinoco::Pipeline::Event.build(
      "wos.board.recognized",
      {
        "screenshot" => { "sourceName" => "Display Capture" },
        "recognition" => {
          "ruleset" => { "mode" => "base", "hidden_letters" => 0, "fake_letters" => 0 },
          "letters" => [ { "char" => "W" }, { "char" => "O" }, { "char" => "S" } ],
          "solved_words" => [ { "state" => "solved", "correct_word" => "WOW" } ]
        }
      },
      occurred_at: "2026-07-13T08:00:00Z"
    )
  end

  before do
    allow(broadcaster).to receive(:broadcast_update_to)
  end

  it "persists latest WOS state, updates the WOS overlay layer, and records projection success" do
    state = handler.call(event)

    expect(JSON.parse(redis.values.fetch(Wos::OverlayStateStore::KEY))).to eq(state)
    expect(state).to include("recognized_at" => "2026-07-13T08:00:00Z")
    expect(accepted_guess_matcher).to have_received(:call).with(previous_state: {}, current_state: state)
    expect(accepted_word_learner).to have_received(:call).with(
      recognition: state.fetch("recognition"),
      observed_at: "2026-07-13T08:00:00Z"
    )
    expect(broadcaster).to have_received(:broadcast_update_to).with(
      "overlay:default",
      target: "overlay_layer_wos_brain",
      layout: false,
      renderable: a_kind_of(WosOverlayLayerComponent)
    )
    expect(status_store).to have_received(:projection_succeeded!)
    expect(status_store).not_to have_received(:projection_failed!)
  end

  it "adds matched Twitch guesses to projection state and learns them with a Twitch source" do
    redis.set(
      Wos::OverlayStateStore::KEY,
      JSON.generate("recognized_at" => "2026-07-13T07:59:58Z", "recognition" => { "remaining_words" => [] })
    )
    accepted_guess = {
      "state" => "solved",
      "correct_word" => "THANK",
      "player" => "MEL",
      "source" => Wos::AcceptedGuessMatcher::SOURCE
    }
    allow(accepted_guess_matcher).to receive(:call).and_return([accepted_guess])

    state = handler.call(event)

    expect(state.dig("recognition", "solved_words")).to include(accepted_guess)
    expect(accepted_guess_matcher).to have_received(:call).with(
      previous_state: { "recognized_at" => "2026-07-13T07:59:58Z", "recognition" => { "remaining_words" => [] } },
      current_state: hash_including("recognized_at" => "2026-07-13T08:00:00Z")
    )
    expect(accepted_word_learner).to have_received(:call).with(
      recognition: { "solved_words" => [accepted_guess] },
      observed_at: "2026-07-13T08:00:00Z",
      source: Wos::AcceptedGuessMatcher::SOURCE
    )
  end


  it "keeps the last valid board when a no-board frame is recognized" do
    previous_state = {
      "recognized_at" => "2026-07-13T07:59:58Z",
      "recognition" => {
        "letters" => [ { "char" => "T" }, { "char" => "H" }, { "char" => "A" }, { "char" => "N" }, { "char" => "K" } ],
        "remaining_words" => [ { "length" => 5, "remaining" => 5 } ]
      }
    }
    redis.set(Wos::OverlayStateStore::KEY, JSON.generate(previous_state))
    empty_event = Orinoco::Pipeline::Event.build(
      "wos.board.recognized",
      {
        "recognition" => {
          "letters" => [],
          "remaining_words" => [],
          "warnings" => ["letter board segmentation found no visible tiles"]
        }
      },
      occurred_at: "2026-07-13T08:00:05Z"
    )

    state = handler.call(empty_event)

    expect(state).to eq(previous_state)
    expect(JSON.parse(redis.values.fetch(Wos::OverlayStateStore::KEY))).to eq(previous_state)
    expect(accepted_guess_matcher).not_to have_received(:call)
    expect(accepted_word_learner).not_to have_received(:call)
    expect(broadcaster).not_to have_received(:broadcast_update_to)
    expect(status_store).not_to have_received(:projection_succeeded!)
    expect(status_store).to have_received(:no_active_board!)
  end
  it "records projection failures and re-raises so the queue message is retried" do
    allow(broadcaster).to receive(:broadcast_update_to).and_raise(RuntimeError, "broadcast exploded")

    expect { handler.call(event) }.to raise_error(RuntimeError, "broadcast exploded")
    expect(status_store).to have_received(:projection_failed!).with(
      "WOSBrain projection failed: RuntimeError: broadcast exploded"
    )
    expect(status_store).not_to have_received(:projection_succeeded!)
  end
end
