# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dioramas::JsonExporter do
  it "exports a deterministic unified graph with schema versioning" do
    diorama = Diorama.create!(
      slug: "orinoco.graph",
      name: "Graph",
      version: "0.1.0",
      visibility: "private"
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
    selector = diorama.nodes.create!(
      slug: "selector.one",
      kind: "selector",
      name: "Selector One",
      description: "Selector description",
      data: {
        "selector" => "obs.placements_for_input_uuid",
        "args" => { "input_uuid" => "{{ event.inputUuid }}" }
      }
    )
    condition = diorama.nodes.create!(
      slug: "condition.one",
      kind: "condition",
      name: "Condition One"
    )
    effect = diorama.nodes.create!(
      slug: "effect.shared",
      kind: "effect",
      name: "Shared Effect"
    )

    diorama.edges.create!(kind: "contains", from_node: affordance, to_node: rule)
    diorama.edges.create!(kind: "uses", from_node: rule, to_node: trigger)
    diorama.edges.create!(kind: "selects", from_node: rule, to_node: selector)
    diorama.edges.create!(kind: "guards", from_node: rule, to_node: condition)
    diorama.edges.create!(kind: "executes", from_node: rule, to_node: effect, data: { "enabled" => false })

    payload = described_class.new(diorama).as_json

    expect(payload).to eq(
      "type" => "diorama",
      "schema_version" => "1",
      "name" => "Graph",
      "slug" => "orinoco.graph",
      "version" => "0.1.0",
      "visibility" => "private",
      "nodes" => [
        { "kind" => "affordance", "slug" => "affordance.root", "name" => "Root", "data" => {} },
        { "kind" => "rule", "slug" => "rule.one", "name" => "Rule One", "data" => {} },
        { "kind" => "trigger", "slug" => "trigger.one", "name" => "Trigger One", "data" => {} },
        {
          "kind" => "selector",
          "slug" => "selector.one",
          "name" => "Selector One",
          "description" => "Selector description",
          "data" => {
            "selector" => "obs.placements_for_input_uuid",
            "args" => { "input_uuid" => "{{ event.inputUuid }}" }
          }
        },
        { "kind" => "condition", "slug" => "condition.one", "name" => "Condition One", "data" => {} },
        { "kind" => "effect", "slug" => "effect.shared", "name" => "Shared Effect", "data" => {} }
      ],
      "edges" => [
        { "kind" => "contains", "from" => "$.nodes[0]", "to" => "$.nodes[1]", "data" => {} },
        { "kind" => "uses", "from" => "$.nodes[1]", "to" => "$.nodes[2]", "data" => {} },
        { "kind" => "selects", "from" => "$.nodes[1]", "to" => "$.nodes[3]", "data" => {} },
        { "kind" => "guards", "from" => "$.nodes[1]", "to" => "$.nodes[4]", "data" => {} },
        { "kind" => "executes", "from" => "$.nodes[1]", "to" => "$.nodes[5]", "data" => { "enabled" => false } }
      ]
    )
  end

  it "keeps node export order stable regardless of insertion order" do
    diorama = Diorama.create!(
      slug: "orinoco.shuffle",
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
