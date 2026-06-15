# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dioramas::JsonImporter do
  let(:graph_payload) do
    {
      "type" => "diorama",
      "schema_version" => "1",
      "slug" => "source.graph",
      "name" => "Source Graph",
      "version" => "0.1.0",
      "visibility" => "private",
      "nodes" => [
        { "kind" => "affordance", "slug" => "affordance.root", "name" => "Root", "data" => {} },
        { "kind" => "rule", "slug" => "rule.one", "name" => "Rule One", "data" => {} },
        { "kind" => "trigger", "slug" => "trigger.one", "name" => "Trigger One", "data" => {} },
        { "kind" => "selector", "slug" => "selector.one", "name" => "Selector One", "data" => {} },
        { "kind" => "condition", "slug" => "condition.one", "name" => "Condition One", "data" => {} },
        { "kind" => "effect", "slug" => "effect.shared", "name" => "Shared Effect", "data" => {} }
      ],
      "edges" => [
        { "kind" => "contains", "from" => "$.nodes[0]", "to" => "$.nodes[1]", "data" => {} },
        { "kind" => "uses", "from" => "$.nodes[1]", "to" => "$.nodes[2]", "data" => {} },
        { "kind" => "selects", "from" => "$.nodes[1]", "to" => "$.nodes[3]", "data" => {} },
        { "kind" => "guards", "from" => "$.nodes[1]", "to" => "$.nodes[4]", "data" => {} },
        { "kind" => "executes", "from" => "$.nodes[1]", "to" => "$.nodes[5]", "data" => {} },
        { "kind" => "executes", "from" => "$.nodes[0]", "to" => "$.nodes[5]", "data" => { "enabled" => false } }
      ]
    }
  end

  it "imports a schema_version 1 graph and preserves shared node references" do
    imported = described_class.call(graph_payload.to_json, name: "Imported Graph")

    expect(imported.name).to eq("Imported Graph")
    expect(imported.slug).not_to eq("source.graph")
    expect(imported.nodes.order(:created_at, :id).pluck(:kind, :slug)).to include(
      [ "affordance", "affordance.root" ],
      [ "rule", "rule.one" ],
      [ "trigger", "trigger.one" ],
      [ "selector", "selector.one" ],
      [ "condition", "condition.one" ],
      [ "effect", "effect.shared" ]
    )
    expect(imported.edges.count).to eq(6)
    expect(imported.edges.where(kind: "executes").pluck(:to_node_id).uniq.length).to eq(1)
    expect(imported.edges.find_by!(kind: "executes", data: { "enabled" => false }).to_node.slug).to eq("effect.shared")
  end

  it "round-trips the graph shape through export and import" do
    imported = described_class.call(graph_payload.to_json, name: "Imported Graph")
    exported = Dioramas::JsonExporter.new(imported).as_json

    expect(exported.slice("schema_version", "version", "visibility", "nodes")).to eq(
      graph_payload.slice("schema_version", "version", "visibility", "nodes")
    )
    expect(exported["edges"]).to eq(
      [
        { "kind" => "contains", "from" => "$.nodes[0]", "to" => "$.nodes[1]", "data" => {} },
        { "kind" => "executes", "from" => "$.nodes[0]", "to" => "$.nodes[5]", "data" => { "enabled" => false } },
        { "kind" => "uses", "from" => "$.nodes[1]", "to" => "$.nodes[2]", "data" => {} },
        { "kind" => "selects", "from" => "$.nodes[1]", "to" => "$.nodes[3]", "data" => {} },
        { "kind" => "guards", "from" => "$.nodes[1]", "to" => "$.nodes[4]", "data" => {} },
        { "kind" => "executes", "from" => "$.nodes[1]", "to" => "$.nodes[5]", "data" => {} }
      ]
    )
  end

  it "rejects unsupported schema versions" do
    expect do
      described_class.call(graph_payload.merge("schema_version" => "2").to_json)
    end.to raise_error(Dioramas::UnsupportedSchemaVersionError, /unsupported schema_version/)
  end

  it "rejects missing nodes and edges arrays" do
    expect do
      described_class.call(graph_payload.except("nodes").to_json)
    end.to raise_error(Dioramas::ImportError, /nodes must be an array/)

    expect do
      described_class.call(graph_payload.except("edges").to_json)
    end.to raise_error(Dioramas::ImportError, /edges must be an array/)
  end

  it "rejects malformed and out of range edge refs" do
    malformed = graph_payload.deep_dup
    malformed["edges"] = [ { "kind" => "contains", "from" => "$.rules[0]", "to" => "$.nodes[1]", "data" => {} } ]

    expect do
      described_class.call(malformed.to_json)
    end.to raise_error(Dioramas::InvalidNodeReferenceError, /must be a \$\.nodes\[N\] reference/)

    out_of_range = graph_payload.deep_dup
    out_of_range["edges"] = [ { "kind" => "contains", "from" => "$.nodes[0]", "to" => "$.nodes[99]", "data" => {} } ]

    expect do
      described_class.call(out_of_range.to_json)
    end.to raise_error(Dioramas::InvalidNodeReferenceError, /out of range/)
  end
end
