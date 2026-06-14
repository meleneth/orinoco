# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dioramas::JsonImporter do
  it "imports a unified graph and preserves shared node references" do
    payload = {
      "type" => "diorama",
      "slug" => "source.graph",
      "name" => "Source Graph",
      "version" => "0.1.0",
      "visibility" => "private",
      "nodes" => [
        {
          "kind" => "affordance",
          "slug" => "affordance.root",
          "name" => "Root",
          "data" => {}
        },
        {
          "kind" => "rule",
          "slug" => "rule.one",
          "name" => "Rule One",
          "data" => {}
        },
        {
          "kind" => "trigger",
          "slug" => "trigger.one",
          "name" => "Trigger One",
          "data" => {}
        },
        {
          "kind" => "effect",
          "slug" => "effect.shared",
          "name" => "Shared Effect",
          "data" => {}
        }
      ],
      "edges" => [
        {
          "kind" => "contains",
          "from" => "$.nodes[0]",
          "to" => "$.nodes[1]"
        },
        {
          "kind" => "uses",
          "from" => "$.nodes[1]",
          "to" => "$.nodes[2]"
        },
        {
          "kind" => "executes",
          "from" => "$.nodes[1]",
          "to" => "$.nodes[3]"
        },
        {
          "kind" => "guards",
          "from" => "$.nodes[1]",
          "to" => "$.nodes[3]"
        }
      ]
    }

    imported = described_class.call(payload.to_json, name: "Imported Graph")

    expect(imported.name).to eq("Imported Graph")
    expect(imported.slug).not_to eq("source.graph")
    expect(imported.nodes.order(:id).pluck(:kind, :slug)).to include(
      [ "affordance", "affordance.root" ],
      [ "rule", "rule.one" ],
      [ "trigger", "trigger.one" ],
      [ "effect", "effect.shared" ]
    )

    shared_target_ids = imported.edges.where(kind: [ "executes", "guards" ]).pluck(:to_node_id)
    expect(shared_target_ids.uniq.length).to eq(1)
    expect(imported.edges.count).to eq(4)
  end

  it "rejects payloads that are not dioramas" do
    expect do
      described_class.call({ "type" => "clip" }.to_json)
    end.to raise_error(Dioramas::ImportError, /must be a diorama/)
  end
end
