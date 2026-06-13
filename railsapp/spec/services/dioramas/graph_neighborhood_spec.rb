# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dioramas::GraphNeighborhood do
  describe ".call" do
    it "returns incoming and outgoing neighborhood for a node" do
      diorama = Diorama.create!(
        slug: "orinoco.graph.test",
        name: "Graph Test",
        version: "0.1.0",
        visibility: "private"
      )

      incoming_node = DioramaNode.create!(
        diorama: diorama,
        slug: "trigger.obs_media_input_playback_ended",
        kind: "trigger",
        name: "Trigger"
      )
      current_node = DioramaNode.create!(
        diorama: diorama,
        slug: "rule.hide_clip_when_playback_ends",
        kind: "rule",
        name: "Rule"
      )
      outgoing_node = DioramaNode.create!(
        diorama: diorama,
        slug: "effect.disable_scene_item",
        kind: "effect",
        name: "Effect",
        data: { "effect" => "obs.scene_item.set_enabled" }
      )

      incoming_edge = DioramaEdge.create!(
        diorama: diorama,
        from_node: incoming_node,
        to_node: current_node,
        kind: "uses"
      )
      outgoing_edge = DioramaEdge.create!(
        diorama: diorama,
        from_node: current_node,
        to_node: outgoing_node,
        kind: "executes"
      )

      result = described_class.call(current_node)

      expect(result[:current]).to include(
        id: current_node.id,
        slug: "rule.hide_clip_when_playback_ends",
        kind: "rule",
        name: "Rule"
      )

      expect(result[:incoming]).to include(
        {
          edge: include(
            id: incoming_edge.id,
            kind: "uses",
            from_node_id: incoming_node.id,
            to_node_id: current_node.id
          ),
          node: include(
            id: incoming_node.id,
            slug: "trigger.obs_media_input_playback_ended",
            kind: "trigger"
          )
        }
      )

      expect(result[:outgoing]).to include(
        {
          edge: include(
            id: outgoing_edge.id,
            kind: "executes",
            from_node_id: current_node.id,
            to_node_id: outgoing_node.id
          ),
          node: include(
            id: outgoing_node.id,
            slug: "effect.disable_scene_item",
            kind: "effect"
          )
        }
      )
    end
  end
end
