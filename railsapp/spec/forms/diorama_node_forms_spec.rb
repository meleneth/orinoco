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
  end
end
