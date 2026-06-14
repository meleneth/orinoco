# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dioramas::Defaults::ClipShow do
  describe ".create!" do
    it "creates the default clip show diorama graph" do
      diorama = described_class.create!

      expect(diorama.slug).to eq("orinoco.clip_show.default")
      expect(diorama.name).to eq("Default Clip Show")
      expect(diorama.version).to eq("0.1.0")

      expect(diorama.nodes.count).to eq(9)
      expect(diorama.edges.count).to eq(8)

      trigger = diorama.nodes.find_by!(slug: "trigger.obs_media_input_playback_ended")
      selector = diorama.nodes.find_by!(slug: "selector.placements_for_input_uuid")
      condition = diorama.nodes.find_by!(slug: "condition.scene_enabled_for_clip_show")
      effect = diorama.nodes.find_by!(slug: "effect.disable_scene_item")
      asset = diorama.nodes.find_by!(slug: "asset.clip_countdown_text_box")
      placement = diorama.nodes.find_by!(slug: "placement.clip_countdown_bottom_right")
      binding = diorama.nodes.find_by!(slug: "binding.clip_countdown_template")

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
      expect(asset.data).to eq(
        "asset_type" => "overlay_text_box",
        "renderer_key" => "text_box",
        "element_key" => "clip_countdown",
        "style_preset" => "obs_panel",
        "content_template" => "Next clip in {{timers.clip_countdown.remaining_label}}",
        "timer" => {
          "timer_key" => "clip_countdown",
          "duration_ms" => 30_000,
          "mode" => "countdown",
          "starts_on" => "clip_show.started",
          "stops_on" => "clip_show.ended",
          "tick_rate_ms" => 250
        }
      )
      expect(placement.data).to eq(
        "placement_type" => "fixed_overlay_position",
        "anchor" => "bottom_right",
        "position" => {
          "x" => 24,
          "y" => 24,
          "unit" => "px"
        },
        "size" => {
          "width" => 320,
          "height" => 80,
          "size_unit" => "px"
        }
      )
      expect(binding.data).to eq(
        "binding_type" => "safe_text_template",
        "template" => "Next clip in {{timers.clip_countdown.remaining_label}}",
        "sample_context" => {
          "timers" => {
            "clip_countdown" => {
              "remaining_label" => "00:30"
            }
          }
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
        ["rule.hide_clip_when_playback_ends", "executes", "effect.disable_scene_item"],
        ["effect.disable_scene_item", "provides", "asset.clip_countdown_text_box"],
        ["asset.clip_countdown_text_box", "places", "placement.clip_countdown_bottom_right"],
        ["asset.clip_countdown_text_box", "binds", "binding.clip_countdown_template"]
      )
    end
  end

  describe ".find_or_create!" do
    it "returns the same bootstrapped diorama on repeated calls" do
      first = described_class.find_or_create!
      second = described_class.find_or_create!

      expect(second.id).to eq(first.id)
      expect(Diorama.where(slug: Dioramas::Defaults::ClipShow::DIORAMA_ATTRIBUTES[:slug]).count).to eq(1)
    end
  end
end
