# frozen_string_literal: true

require "rails_helper"

RSpec.describe DioramaNodeForms do
  let(:diorama) do
    Diorama.create!(
      slug: "orinoco.diorama.forms",
      name: "Forms Diorama",
      version: "0.1.0",
      visibility: "private"
    )
  end

  describe DioramaNodeForms::Trigger do
    it "writes the expected event payload" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "trigger.node",
        kind: "trigger",
        name: "Trigger Node",
        data: { "event" => "obs.media_input.playback_ended" }
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Trigger",
        description: "Updated description",
        event: "twitch.chat.message_received"
      )

      expect(form).to be_valid
      expect(form.save).to eq(true)
      expect(node.reload.data).to eq("event" => "twitch.chat.message_received")
      expect(node.name).to eq("Updated Trigger")
      expect(node.description).to eq("Updated description")
    end
  end

  describe DioramaNodeForms::Selector do
    it "writes nested args" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "selector.node",
        kind: "selector",
        name: "Selector Node",
        data: { "selector" => "obs.placements_for_input_uuid", "args" => { "input_uuid" => "old" } }
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Selector",
        selector: "obs.placements_for_input_uuid",
        args_input_uuid: "{{ event.inputUuid }}"
      )

      expect(form).to be_valid
      expect(form.save).to eq(true)
      expect(node.reload.data).to eq(
        "selector" => "obs.placements_for_input_uuid",
        "args" => {
          "input_uuid" => "{{ event.inputUuid }}"
        }
      )
    end
  end

  describe DioramaNodeForms::Condition do
    it "writes nested args" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "condition.node",
        kind: "condition",
        name: "Condition Node",
        data: { "condition" => "scene_enabled_for_affordance", "args" => { "affordance" => "clip_show", "scene_name" => "old" } }
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Condition",
        condition: "scene_enabled_for_affordance",
        args_affordance: "clip_show",
        args_scene_name: "{{ placement.sceneName }}"
      )

      expect(form).to be_valid
      expect(form.save).to eq(true)
      expect(node.reload.data).to eq(
        "condition" => "scene_enabled_for_affordance",
        "args" => {
          "affordance" => "clip_show",
          "scene_name" => "{{ placement.sceneName }}"
        }
      )
    end
  end

  describe DioramaNodeForms::Effect do
    it "writes nested args and boolean enabled" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "effect.node",
        kind: "effect",
        name: "Effect Node",
        data: {
          "effect" => "obs.scene_item.set_enabled",
          "args" => {
            "scene_name" => "old",
            "scene_item_id" => "old",
            "enabled" => false
          }
        }
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Effect",
        effect: "obs.scene_item.set_enabled",
        args_scene_name: "{{ placement.sceneName }}",
        args_scene_item_id: "{{ placement.sceneItemId }}",
        enabled: "1"
      )

      expect(form).to be_valid
      expect(form.save).to eq(true)
      expect(node.reload.data).to eq(
        "effect" => "obs.scene_item.set_enabled",
        "args" => {
          "scene_name" => "{{ placement.sceneName }}",
          "scene_item_id" => "{{ placement.sceneItemId }}",
          "enabled" => true
        }
      )
    end
  end

  describe DioramaNodeForms::Asset do
    it "validates image value" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "asset.node",
        kind: "asset",
        name: "Asset Node",
        data: {
          "asset_type" => "image",
          "image" => {
            "storage" => "inline",
            "media_type" => "image/png",
            "encoding" => "base64",
            "data" => "not-base64",
            "sha256" => "abc123",
            "byte_size" => 10
          }
        }
      )

      form = described_class.new(node)

      expect(form).not_to be_valid
      expect(form.errors.full_messages.join(" ")).to include("image inline raster images must use base64 encoding")
    end

    it "accepts valid inline SVG image data" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "asset.svg.node",
        kind: "asset",
        name: "Asset Node"
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Asset",
        asset_type: "image",
        image_storage: "inline",
        image_media_type: "image/svg+xml",
        image_encoding: "utf8",
        image_data: "<svg xmlns='http://www.w3.org/2000/svg'></svg>",
        image_sha256: "abc123",
        image_byte_size: "64",
        image_width: "16",
        image_height: "16"
      )

      expect(form).to be_valid
      expect(form.save).to eq(true)
      expect(node.reload.data).to include(
        "asset_type" => "image"
      )
      expect(node.reload.data["image"]).to include(
        "storage" => "inline",
        "media_type" => "image/svg+xml",
        "encoding" => "utf8"
      )
    end

    it "accepts valid overlay text box config" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "asset.overlay.node",
        kind: "asset",
        name: "Overlay Asset"
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Overlay Asset",
        asset_type: "overlay_text_box",
        renderer_key: "text_box",
        element_key: "clip_countdown",
        style_preset: "obs_panel",
        content_template: "Next clip in {{timers.clip_countdown.remaining_label}}",
        timer_key: "clip_countdown",
        duration_ms: "30000",
        mode: "countdown",
        starts_on: "clip_show.started",
        stops_on: "clip_show.ended",
        tick_rate_ms: "250"
      )

      expect(form).to be_valid
      expect(form.save).to eq(true)
      expect(node.reload.data).to eq(
        "asset_type" => "overlay_text_box",
        "renderer_key" => "text_box",
        "element_key" => "clip_countdown",
        "style_preset" => "obs_panel",
        "content_template" => "Next clip in {{timers.clip_countdown.remaining_label}}",
        "timer" => {
          "timer_key" => "clip_countdown",
          "duration_ms" => 30000,
          "mode" => "countdown",
          "starts_on" => "clip_show.started",
          "stops_on" => "clip_show.ended",
          "tick_rate_ms" => 250
        }
      )
    end

    it "rejects an unknown renderer key" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "asset.invalid.renderer",
        kind: "asset",
        name: "Overlay Asset"
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Overlay Asset",
        asset_type: "overlay_text_box",
        renderer_key: "Kernel",
        element_key: "clip_countdown",
        style_preset: "obs_panel",
        content_template: "Next clip in {{timers.clip_countdown.remaining_label}}"
      )

      expect(form).not_to be_valid
      expect(form.errors.full_messages.join(" ")).to include("renderer_key is invalid")
    end
  end

  describe DioramaNodeForms::Placement do
    it "accepts valid fixed overlay position config" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "placement.node",
        kind: "placement",
        name: "Placement Node"
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Placement",
        placement_type: "fixed_overlay_position",
        anchor: "bottom_right",
        x: "24",
        y: "24",
        unit: "px",
        width: "320",
        height: "80",
        size_unit: "px"
      )

      expect(form).to be_valid
      expect(form.save).to eq(true)
      expect(node.reload.data).to eq(
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
    end

    it "rejects invalid anchor and unit values" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "placement.invalid.node",
        kind: "placement",
        name: "Placement Node"
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Placement",
        placement_type: "fixed_overlay_position",
        anchor: "north",
        x: "24",
        y: "24",
        unit: "em",
        width: "320",
        height: "80",
        size_unit: "px"
      )

      expect(form).not_to be_valid
      expect(form.errors.full_messages.join(" ")).to include("anchor is invalid")
      expect(form.errors.full_messages.join(" ")).to include("unit is invalid")
    end
  end

  describe DioramaNodeForms::Binding do
    it "accepts valid safe text template config" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "binding.node",
        kind: "binding",
        name: "Binding Node"
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Binding",
        binding_type: "safe_text_template",
        template: "Next clip in {{timers.clip_countdown.remaining_label}}",
        sample_context_json: JSON.pretty_generate(
          "timers" => {
            "clip_countdown" => {
              "remaining_label" => "00:30"
            }
          }
        )
      )

      expect(form).to be_valid
      expect(form.save).to eq(true)
      expect(node.reload.data).to eq(
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
    end

    it "rejects invalid placeholders" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "binding.invalid.node",
        kind: "binding",
        name: "Binding Node"
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Binding",
        binding_type: "safe_text_template",
        template: "{{foo()}}",
        sample_context_json: "{}"
      )

      expect(form).not_to be_valid
      expect(form.errors.full_messages.join(" ")).to include("invalid placeholder")
    end

    it "rejects invalid sample context JSON" do
      node = DioramaNode.create!(
        diorama: diorama,
        slug: "binding.invalid.json",
        kind: "binding",
        name: "Binding Node"
      )

      form = described_class.new(node)
      form.assign_attributes(
        name: "Updated Binding",
        binding_type: "safe_text_template",
        template: "Hello {{viewer.name}}",
        sample_context_json: "{not json"
      )

      expect(form).not_to be_valid
      expect(form.errors.full_messages.join(" ")).to include("Sample context json must be valid JSON")
    end
  end
end
