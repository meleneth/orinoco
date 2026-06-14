# frozen_string_literal: true

require "tempfile"
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

  describe "GET /dioramas/:id/export" do
    it "downloads a JSON export with path-based edge references" do
      get export_diorama_path(diorama)

      payload = JSON.parse(response.body)

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("application/json")
      expect(payload["type"]).to eq("diorama")
      expect(payload["affordances"].first).to include(
        "slug" => "affordance.clip_show",
        "name" => "Clip Show Affordance"
      )
      expect(payload["affordances"].first).not_to have_key("id")
      expect(payload["edges"].first).to include(
        "kind" => "contains",
        "from" => "$.affordances[0]",
        "to" => "$.rules[0]"
      )
      expect(payload).not_to have_key("id")
      expect(payload).not_to have_key("diorama_id")
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

    it "shows overlay child add links from effect and asset nodes" do
      effect_node = diorama.nodes.find_by!(slug: "effect.disable_scene_item")
      asset_node = diorama.nodes.find_by!(slug: "asset.clip_countdown_text_box")

      get diorama_node_path(diorama, effect_node)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Add asset")

      get diorama_node_path(diorama, asset_node)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Add placement")
      expect(response.body).to include("Add binding")
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

    it "allows editing the overlay text box asset" do
      node = diorama.nodes.find_by!(slug: "asset.clip_countdown_text_box")

      patch diorama_node_path(diorama, node), params: {
        diorama_node_form: {
          name: node.name,
          description: node.description,
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
        }
      }

      expect(response).to redirect_to(diorama_node_path(diorama, node))

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

    it "allows editing the placement config" do
      node = diorama.nodes.find_by!(slug: "placement.clip_countdown_bottom_right")

      patch diorama_node_path(diorama, node), params: {
        diorama_node_form: {
          name: node.name,
          description: node.description,
          placement_type: "fixed_overlay_position",
          anchor: "bottom_right",
          x: "24",
          y: "24",
          unit: "px",
          width: "320",
          height: "80",
          size_unit: "px"
        }
      }

      expect(response).to redirect_to(diorama_node_path(diorama, node))

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

    it "allows editing the binding template" do
      node = diorama.nodes.find_by!(slug: "binding.clip_countdown_template")

      patch diorama_node_path(diorama, node), params: {
        diorama_node_form: {
          name: node.name,
          description: node.description,
          binding_type: "safe_text_template",
          template: "Next clip in {{timers.clip_countdown.remaining_label}}",
          sample_context_json: JSON.pretty_generate(
            "timers" => {
              "clip_countdown" => {
                "remaining_label" => "00:30"
              }
            }
          )
        }
      }

      expect(response).to redirect_to(diorama_node_path(diorama, node))

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

    it "rejects invalid JSON in fallback editor paths" do
      fallback = diorama.nodes.create!(
        slug: "fallback.raw_json",
        kind: "fallback",
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

  describe "POST /dioramas/import" do
    it "imports a diorama under a new name" do
      json = Dioramas::JsonExporter.new(diorama).to_json

      Tempfile.create(["diorama-export", ".json"]) do |file|
        file.write(json)
        file.flush
        file.close

        uploaded_file = Rack::Test::UploadedFile.new(file.path, "application/json")

        post import_dioramas_path, params: {
          diorama_import: {
            file: uploaded_file,
            name: "Cloned Clip Show"
          }
        }
      end

      imported = Diorama.find_by!(name: "Cloned Clip Show")

      expect(response).to redirect_to(diorama_path(imported))
      expect(imported.slug).not_to eq(diorama.slug)
      expect(imported.nodes.count).to eq(diorama.nodes.count)
      expect(imported.edges.count).to eq(diorama.edges.count)
    end
  end
end
