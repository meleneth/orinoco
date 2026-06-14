# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dioramas::JsonExporter do
  it "exports a deterministic unified graph with file-local node refs" do
    diorama = Diorama.create!(
      slug: "orinoco.graph",
      name: "Graph",
      version: "0.1.0",
      visibility: "private"
    )

    effect = diorama.nodes.create!(
      slug: "effect.shared",
      kind: "effect",
      name: "Shared Effect"
    )
    affordance = diorama.nodes.create!(
      slug: "affordance.root",
      kind: "affordance",
      name: "Root"
    )
    rule = diorama.nodes.create!(
      slug: "rule.one",
      kind: "rule",
      name: "Rule One"
    )
    trigger = diorama.nodes.create!(
      slug: "trigger.one",
      kind: "trigger",
      name: "Trigger One"
    )

    diorama.edges.create!(kind: "contains", from_node: affordance, to_node: rule)
    diorama.edges.create!(kind: "uses", from_node: rule, to_node: trigger)
    diorama.edges.create!(kind: "executes", from_node: rule, to_node: effect)
    diorama.edges.create!(kind: "guards", from_node: rule, to_node: effect)

    payload = described_class.new(diorama).as_json

    expect(payload).to eq(
      "type" => "diorama",
      "slug" => "orinoco.graph",
      "name" => "Graph",
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
    )
  end

  it "keeps node export order stable regardless of insertion order" do
    diorama = Diorama.create!(
      slug: "orinooc.shuffle",
      name: "Shuffle",
      version: "0.1.0",
      visibility: "private"
    )

    diorama.nodes.create!(slug: "effect.one", kind: "effect", name: "Effect One")
    diorama.nodes.create!(slug: "rule.one", kind: "rule", name: "Rule One")
    diorama.nodes.create!(slug: "affordance.one", kind: "affordance", name: "Affordance One")
    diorama.nodes.create!(slug: "trigger.one", kind: "trigger", name: "Trigger One")

    payload = described_class.new(diorama).as_json

    expect(payload["nodes"].map { |node| [ node["kind"], node["slug"] ] }).to eq(
      [
        [ "affordance", "affordance.one" ],
        [ "rule", "rule.one" ],
        [ "trigger", "trigger.one" ],
        [ "effect", "effect.one" ]
      ]
    )
  end
end
