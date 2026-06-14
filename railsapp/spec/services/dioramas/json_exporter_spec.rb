# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dioramas::JsonExporter do
  let!(:diorama) do
    Dioramas::Defaults::ClipShow.find_or_create!
  end

  it "exports dioramas as a path-referenced JSON tree" do
    payload = described_class.new(diorama).as_json

    expect(payload["type"]).to eq("diorama")
    expect(payload["name"]).to eq("Default Clip Show")
    expect(payload["affordances"].first).to include(
      "slug" => "affordance.clip_show",
      "name" => "Clip Show Affordance"
    )
    expect(payload["affordances"].first).not_to have_key("id")
    expect(payload["rules"].first).to include("slug" => "rule.hide_clip_when_playback_ends")
    expect(payload["edges"]).to include(
      include(
        "kind" => "contains",
        "from" => "$.affordances[0]",
        "to" => "$.rules[0]"
      )
    )
  end

  it "does not leak database identifiers" do
    payload = described_class.new(diorama).as_json

    expect(payload.keys).not_to include("id", "diorama_id")
    %w[affordances rules triggers selectors conditions effects assets placements bindings fallbacks capabilities test_events runtime_traces].each do |array_key|
      Array(payload[array_key]).each do |node|
        expect(node.keys).not_to include("id", "diorama_id", "from_node_id", "to_node_id")
      end
    end
  end
end
