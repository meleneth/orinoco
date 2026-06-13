# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dioramas::Defaults::ClipShow do
  describe ".create!" do
    it "creates the default clip show diorama graph" do
      diorama = described_class.create!

      expect(diorama.slug).to eq("orinoco.clip_show.default")
      expect(diorama.name).to eq("Default Clip Show")
      expect(diorama.version).to eq("0.1.0")

      expect(diorama.nodes.count).to eq(6)
      expect(diorama.edges.count).to eq(5)

      trigger = diorama.nodes.find_by!(slug: "trigger.obs_media_input_playback_ended")
      selector = diorama.nodes.find_by!(slug: "selector.placements_for_input_uuid")
      condition = diorama.nodes.find_by!(slug: "condition.scene_enabled_for_clip_show")
      effect = diorama.nodes.find_by!(slug: "effect.disable_scene_item")

      expect(trigger.data).to eq(
        "event" => "obs.media_input.playback_ended"
      )
      expect(selector.data).to eq(
        "selector" => "obs.placements_for_input_uuid",
        "args" => {
          "input_uuid" => "{{ event.inputUuid }}"
        }
      )
      expect(condition.data).to eq(
        "condition" => "scene_enabled_for_affordance",
        "args" => {
          "affordance" => "clip_show",
          "scene_name" => "{{ placement.sceneName }}"
        }
      )
      expect(effect.data).to eq(
        "effect" => "obs.scene_item.set_enabled",
        "args" => {
          "scene_name" => "{{ placement.sceneName }}",
          "scene_item_id" => "{{ placement.sceneItemId }}",
          "enabled" => false
        }
      )

      edge_tuples = diorama.edges.includes(:from_node, :to_node).map do |edge|
        [edge.from_node.slug, edge.kind, edge.to_node.slug]
      end

      expect(edge_tuples).to include(
        ["affordance.clip_show", "contains", "rule.hide_clip_when_playback_ends"],
        ["rule.hide_clip_when_playback_ends", "uses", "trigger.obs_media_input_playback_ended"],
        ["rule.hide_clip_when_playback_ends", "selects", "selector.placements_for_input_uuid"],
        ["rule.hide_clip_when_playback_ends", "guards", "condition.scene_enabled_for_clip_show"],
        ["rule.hide_clip_when_playback_ends", "executes", "effect.disable_scene_item"]
      )
    end
  end
end
