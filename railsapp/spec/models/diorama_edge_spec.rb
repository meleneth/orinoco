# frozen_string_literal: true

require "rails_helper"

RSpec.describe DioramaEdge, type: :model do
  let(:diorama) do
    Diorama.create!(
      slug: "orinoco.clip_show.default",
      name: "Default Clip Show",
      version: "0.1.0",
      visibility: "private"
    )
  end

  let(:from_node) do
    DioramaNode.create!(
      diorama: diorama,
      slug: "rule.hide_clip_when_playback_ends",
      kind: "rule",
      name: "Hide Clip When Playback Ends"
    )
  end

  let(:to_node) do
    DioramaNode.create!(
      diorama: diorama,
      slug: "effect.disable_scene_item",
      kind: "effect",
      name: "Disable Scene Item",
      data: { "effect" => "obs.scene_item.set_enabled" }
    )
  end

  subject(:edge) do
    described_class.new(
      diorama: diorama,
      from_node: from_node,
      to_node: to_node,
      kind: "executes"
    )
  end

  it "is valid with required attributes" do
    expect(edge).to be_valid
  end

  it "requires kind" do
    edge.kind = nil

    expect(edge).to be_invalid
    expect(edge.errors[:kind]).to include("can't be blank")
  end

  it "validates kind inclusion" do
    edge.kind = "flows_to"

    expect(edge).to be_invalid
    expect(edge.errors[:kind]).to include("is not included in the list")
  end

  it "validates uniqueness of diorama, from_node, to_node, and kind" do
    described_class.create!(
      diorama: diorama,
      from_node: from_node,
      to_node: to_node,
      kind: "executes"
    )

    expect(edge).to be_invalid
    expect(edge.errors[:kind]).to include("has already been taken")
  end

  it "rejects cross-diorama from_node" do
    other_diorama = Diorama.create!(
      slug: "orinoco.clip_show.alt",
      name: "Alt Clip Show",
      version: "0.1.0",
      visibility: "private"
    )

    other_from_node = DioramaNode.create!(
      diorama: other_diorama,
      slug: "rule.alt",
      kind: "rule",
      name: "Alt Rule"
    )

    invalid_edge = described_class.new(
      diorama: diorama,
      from_node: other_from_node,
      to_node: to_node,
      kind: "executes"
    )

    expect(invalid_edge).to be_invalid
    expect(invalid_edge.errors[:from_node_id]).to include("must belong to the same diorama")
  end

  it "rejects cross-diorama to_node" do
    other_diorama = Diorama.create!(
      slug: "orinoco.clip_show.alt",
      name: "Alt Clip Show",
      version: "0.1.0",
      visibility: "private"
    )

    other_to_node = DioramaNode.create!(
      diorama: other_diorama,
      slug: "effect.alt",
      kind: "effect",
      name: "Alt Effect",
      data: { "effect" => "noop" }
    )

    invalid_edge = described_class.new(
      diorama: diorama,
      from_node: from_node,
      to_node: other_to_node,
      kind: "executes"
    )

    expect(invalid_edge).to be_invalid
    expect(invalid_edge.errors[:to_node_id]).to include("must belong to the same diorama")
  end
end
