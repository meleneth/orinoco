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
  let(:status_store) do
    instance_double(
      Wos::StatusStore,
      projection_succeeded!: nil,
      projection_failed!: nil
    )
  end
  let(:handler) do
    described_class.new(
      redis: redis,
      broadcaster: broadcaster,
      accepted_word_learner: accepted_word_learner,
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

  it "records projection failures and re-raises so the queue message is retried" do
    allow(broadcaster).to receive(:broadcast_update_to).and_raise(RuntimeError, "broadcast exploded")

    expect { handler.call(event) }.to raise_error(RuntimeError, "broadcast exploded")
    expect(status_store).to have_received(:projection_failed!).with(
      "WOSBrain projection failed: RuntimeError: broadcast exploded"
    )
    expect(status_store).not_to have_received(:projection_succeeded!)
  end
end
