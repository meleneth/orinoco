# frozen_string_literal: true

require "spec_helper"
require "d2r/run_inference"
require "orinoco/pipeline/event"

RSpec.describe D2r::RunInference do
  let(:inference) { described_class.new }
  let(:state) { { "game" => { "id" => "game-1", "started_at" => "2026-11-23T10:00:00Z" }, "visited_areas" => [], "previous_run_kind" => nil } }

  def enter(area)
    event = Orinoco::Pipeline::Event.build("d2r.area.changed", { "area" => area },
      occurred_at: "2026-11-23T10:01:00Z")
    inference.observe(state, event)
  end

  it "infers Countess from tower progression without selection" do
    enter("Black Marsh")
    expect(state["run"]).to be_nil
    enter("Forgotten Tower")
    expect(state.dig("run", "kind")).to eq("countess")
    expect(state.dig("run", "confidence")).to eq(0.75)
    enter("Tower Cellar Level 1")
    expect(state.dig("run", "confidence")).to eq(0.90)
    enter("Tower Cellar Level 5")
    expect(state.dig("run", "confidence")).to eq(0.99)
    expect(state.dig("run", "evidence")).to include("Tower Cellar Level 5")
  end

  it "classifies Mephisto and other specific destinations" do
    enter("Durance of Hate Level 2")
    enter("Durance of Hate Level 3")
    expect(state.dig("run", "kind")).to eq("mephisto")
  end

  it "does not create a run outside a game" do
    state["game"] = nil
    enter("Tower Cellar Level 5")
    expect(state["run"]).to be_nil
  end

  it "recognizes matching prior runs as repeats" do
    state["previous_run_kind"] = "countess"
    enter("Forgotten Tower")
    expect(state.dig("run", "repeated")).to be(true)
  end
end
