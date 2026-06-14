# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dioramas", type: :request do
  let!(:diorama) do
    Dioramas::Defaults::ClipShow.find_or_create!
  end

  around do |example|
    suppress_output { example.run }
  end

  describe "GET /dioramas" do
    it "returns success and lists dioramas" do
      get dioramas_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Dioramas")
      expect(response.body).to include(diorama.name)
      expect(response.body).to include(diorama.slug)
      expect(response.body).to include(diorama.version)
      expect(response.body).to include(diorama.visibility)
    end
  end

  describe "GET /dioramas/:id" do
    it "opens the default Clip Show diorama and shows only root affordance nodes" do
      get diorama_path(diorama)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Root affordance nodes")
      expect(response.body).to include("affordance.clip_show")
      expect(response.body).to include("1 child")
      expect(response.body).not_to include("trigger.obs_media_input_playback_ended")
      expect(response.body).not_to include("selector.placements_for_input_uuid")
      expect(response.body).not_to include("condition.scene_enabled_for_clip_show")
      expect(response.body).not_to include("effect.disable_scene_item")
    end
  end

  describe "GET /dioramas/:id/nodes/:id" do
    it "opens a node editor with adjacency panels" do
      node = diorama.nodes.find_by!(slug: "trigger.obs_media_input_playback_ended")

      get diorama_node_path(diorama, node)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Incoming")
      expect(response.body).to include("Current data")
      expect(response.body).to include("Outgoing")
      expect(response.body).to include("obs.media_input.playback_ended")
      expect(response.body).to include("rule.hide_clip_when_playback_ends")
    end

    it "allows editing the trigger event" do
      node = diorama.nodes.find_by!(slug: "trigger.obs_media_input_playback_ended")

      patch diorama_node_path(diorama, node), params: {
        diorama_node_form: {
          name: node.name,
          description: node.description,
          event: "twitch.chat.message_received"
        }
      }

      expect(response).to redirect_to(diorama_node_path(diorama, node))
      expect(node.reload.data).to eq("event" => "twitch.chat.message_received")
    end

    it "allows editing the effect enabled field" do
      node = diorama.nodes.find_by!(slug: "effect.disable_scene_item")

      patch diorama_node_path(diorama, node), params: {
        diorama_node_form: {
          name: node.name,
          description: node.description,
          effect: "obs.scene_item.set_enabled",
          args_scene_name: "{{ placement.sceneName }}",
          args_scene_item_id: "{{ placement.sceneItemId }}",
          enabled: "1"
        }
      }

      expect(response).to redirect_to(diorama_node_path(diorama, node))

      expect(node.reload.data).to eq(
        "effect" => "obs.scene_item.set_enabled",
        "args" => {
          "scene_name" => "{{ placement.sceneName }}",
          "scene_item_id" => "{{ placement.sceneItemId }}",
          "enabled" => true
        }
      )
    end

    it "rejects invalid JSON in fallback editor paths" do
      fallback = diorama.nodes.create!(
        slug: "binding.fallback",
        kind: "binding",
        name: "Fallback Binding",
        data: { "ok" => true }
      )

      patch diorama_node_path(diorama, fallback), params: {
        diorama_node_form: {
          name: fallback.name,
          description: fallback.description,
          raw_data: "{not json"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must be valid JSON")
    end

    it "renders inline SVG previews without crashing" do
      asset = diorama.nodes.create!(
        slug: "asset.inline_svg",
        kind: "asset",
        name: "Inline SVG Asset",
        data: {
          "asset_type" => "image",
          "image" => {
            "storage" => "inline",
            "media_type" => "image/svg+xml",
            "encoding" => "utf8",
            "data" => "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1 1'></svg>",
            "sha256" => "abc123",
            "byte_size" => 64,
            "width" => 1,
            "height" => 1
          }
        }
      )

      get diorama_node_path(diorama, asset)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Inline preview")
      expect(response.body).to include("data:image/svg+xml;utf8,")
    end
  end

  describe "POST /dioramas/bootstrap_default" do
    it "ensures the default diorama exists" do
      Diorama.where(slug: Dioramas::Defaults::ClipShow::DIORAMA_ATTRIBUTES[:slug]).delete_all

      post bootstrap_default_dioramas_path

      expect(response).to redirect_to(diorama_path(Diorama.find_by!(slug: Dioramas::Defaults::ClipShow::DIORAMA_ATTRIBUTES[:slug])))
    end
  end
end
