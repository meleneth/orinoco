module Dioramas
  module Defaults
    class ClipShow
      DIORAMA_ATTRIBUTES = {
        slug: "orinoco.clip_show.default",
        name: "Default Clip Show",
        version: "0.1.0"
      }.freeze

      def self.create!
        new.create!
      end

      def self.find_or_create!
        Diorama.find_by(slug: DIORAMA_ATTRIBUTES[:slug]) || create!
      end

      def create!
        ActiveRecord::Base.transaction do
          diorama = Diorama.create!(DIORAMA_ATTRIBUTES)
          nodes = create_nodes!(diorama)
          create_edges!(diorama, nodes)
          diorama
        end
      end

      private

      def create_nodes!(diorama)
        {
          "affordance.clip_show" => diorama.nodes.create!(
            slug: "affordance.clip_show",
            kind: "affordance",
            name: "Clip Show Affordance"
          ),
          "rule.hide_clip_when_playback_ends" => diorama.nodes.create!(
            slug: "rule.hide_clip_when_playback_ends",
            kind: "rule",
            name: "Hide Clip When Playback Ends"
          ),
          "trigger.obs_media_input_playback_ended" => diorama.nodes.create!(
            slug: "trigger.obs_media_input_playback_ended",
            kind: "trigger",
            name: "OBS Media Input Playback Ended",
            data: {
              "event" => "obs.media_input.playback_ended"
            }
          ),
          "selector.placements_for_input_uuid" => diorama.nodes.create!(
            slug: "selector.placements_for_input_uuid",
            kind: "selector",
            name: "Placements For Input UUID",
            data: {
              "selector" => "obs.placements_for_input_uuid",
              "args" => {
                "input_uuid" => "{{ event.inputUuid }}"
              }
            }
          ),
          "condition.scene_enabled_for_clip_show" => diorama.nodes.create!(
            slug: "condition.scene_enabled_for_clip_show",
            kind: "condition",
            name: "Scene Enabled For Clip Show",
            data: {
              "condition" => "scene_enabled_for_affordance",
              "args" => {
                "affordance" => "clip_show",
                "scene_name" => "{{ placement.sceneName }}"
              }
            }
          ),
          "effect.disable_scene_item" => diorama.nodes.create!(
            slug: "effect.disable_scene_item",
            kind: "effect",
            name: "Disable Scene Item",
            data: {
              "effect" => "obs.scene_item.set_enabled",
              "args" => {
                "scene_name" => "{{ placement.sceneName }}",
                "scene_item_id" => "{{ placement.sceneItemId }}",
                "enabled" => false
              }
            }
          ),
          "asset.clip_countdown_text_box" => diorama.nodes.create!(
            slug: "asset.clip_countdown_text_box",
            kind: "asset",
            name: "Clip Countdown Text Box",
            data: {
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
            }
          ),
          "placement.clip_countdown_bottom_right" => diorama.nodes.create!(
            slug: "placement.clip_countdown_bottom_right",
            kind: "placement",
            name: "Clip Countdown Bottom Right",
            data: {
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
            }
          ),
          "binding.clip_countdown_template" => diorama.nodes.create!(
            slug: "binding.clip_countdown_template",
            kind: "binding",
            name: "Clip Countdown Template",
            data: {
              "binding_type" => "safe_text_template",
              "template" => "Next clip in {{timers.clip_countdown.remaining_label}}",
              "sample_context" => {
                "timers" => {
                  "clip_countdown" => {
                    "remaining_label" => "00:30"
                  }
                }
              }
            }
          )
        }
      end

      def create_edges!(diorama, nodes)
        create_edge!(
          diorama: diorama,
          nodes: nodes,
          from_slug: "affordance.clip_show",
          to_slug: "rule.hide_clip_when_playback_ends",
          kind: "contains"
        )

        create_edge!(
          diorama: diorama,
          nodes: nodes,
          from_slug: "rule.hide_clip_when_playback_ends",
          to_slug: "trigger.obs_media_input_playback_ended",
          kind: "uses"
        )

        create_edge!(
          diorama: diorama,
          nodes: nodes,
          from_slug: "rule.hide_clip_when_playback_ends",
          to_slug: "selector.placements_for_input_uuid",
          kind: "selects"
        )

        create_edge!(
          diorama: diorama,
          nodes: nodes,
          from_slug: "rule.hide_clip_when_playback_ends",
          to_slug: "condition.scene_enabled_for_clip_show",
          kind: "guards"
        )

        create_edge!(
          diorama: diorama,
          nodes: nodes,
          from_slug: "rule.hide_clip_when_playback_ends",
          to_slug: "effect.disable_scene_item",
          kind: "executes"
        )

        create_edge!(
          diorama: diorama,
          nodes: nodes,
          from_slug: "effect.disable_scene_item",
          to_slug: "asset.clip_countdown_text_box",
          kind: "provides"
        )

        create_edge!(
          diorama: diorama,
          nodes: nodes,
          from_slug: "asset.clip_countdown_text_box",
          to_slug: "placement.clip_countdown_bottom_right",
          kind: "places"
        )

        create_edge!(
          diorama: diorama,
          nodes: nodes,
          from_slug: "asset.clip_countdown_text_box",
          to_slug: "binding.clip_countdown_template",
          kind: "binds"
        )
      end

      def create_edge!(diorama:, nodes:, from_slug:, to_slug:, kind:)
        diorama.edges.create!(
          from_node: nodes.fetch(from_slug),
          to_node: nodes.fetch(to_slug),
          kind: kind
        )
      end
    end
  end
end
