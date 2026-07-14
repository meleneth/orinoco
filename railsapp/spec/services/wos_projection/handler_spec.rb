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
  let(:event) do
    Orinoco::Pipeline::Event.build(
      "wos.board.recognized",
      {
        "screenshot" => { "sourceName" => "Display Capture" },
        "recognition" => {
          "ruleset" => { "mode" => "base", "hidden_letters" => 0, "fake_letters" => 0 },
          "letters" => [ { "char" => "W" }, { "char" => "O" }, { "char" => "S" } ]
        }
      },
      occurred_at: "2026-07-13T08:00:00Z"
    )
  end

  before do
    allow(broadcaster).to receive(:broadcast_update_to)
  end

  it "persists latest WOS state and updates the WOS overlay layer" do
    state = described_class.new(redis: redis, broadcaster: broadcaster).call(event)

    expect(JSON.parse(redis.values.fetch(Wos::OverlayStateStore::KEY))).to eq(state)
    expect(state).to include("recognized_at" => "2026-07-13T08:00:00Z")
    expect(broadcaster).to have_received(:broadcast_update_to).with(
      "overlay:default",
      target: "overlay_layer_wos_brain",
      layout: false,
      renderable: a_kind_of(WosOverlayLayerComponent)
    )
  end
end