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
