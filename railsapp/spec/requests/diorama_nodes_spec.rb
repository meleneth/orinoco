# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Diorama nodes", type: :request do
  let!(:diorama) do
    Dioramas::Defaults::ClipShow.find_or_create!
  end

  around do |example|
    suppress_output { example.run }
  end

  let(:rule) do
    diorama.nodes.find_by!(slug: "rule.hide_clip_when_playback_ends")
  end

  let(:trigger) do
    diorama.nodes.find_by!(slug: "trigger.obs_media_input_playback_ended")
  end

  let(:selector) do
    diorama.nodes.find_by!(slug: "selector.placements_for_input_uuid")
  end

  let(:condition) do
    diorama.nodes.find_by!(slug: "condition.scene_enabled_for_clip_show")
  end

  let(:effect) do
    diorama.nodes.find_by!(slug: "effect.disable_scene_item")
  end

  describe "GET /dioramas/:id/nodes/:id/edit" do
    it "links adjacency cards to connected node editors and renders add links" do
      get edit_diorama_node_path(diorama, rule)

      executes_add_href = ERB::Util.html_escape(
        new_diorama_node_path(diorama, parent_node_slug: rule.slug, edge_kind: "executes", kind: "effect")
      )
      uses_add_href = ERB::Util.html_escape(
        new_diorama_node_path(diorama, parent_node_slug: rule.slug, edge_kind: "uses", kind: "trigger")
      )

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(href="#{edit_diorama_node_path(diorama, trigger)}"))
      expect(response.body).to include(%(href="#{edit_diorama_node_path(diorama, effect)}"))
      expect(response.body).to include(%(href="#{executes_add_href}"))
      expect(response.body).to include(%(href="#{uses_add_href}"))
      expect(response.body).to include("Add effect")
      expect(response.body).to include("Add trigger")
    end
  end

  describe "GET /dioramas/:id/nodes/new" do
    it "renders a contextual create form for the requested child kind" do
      get new_diorama_node_path(diorama, parent_node_slug: rule.slug, edge_kind: "executes", kind: "effect")

      expected_action = ERB::Util.html_escape(
        diorama_nodes_path(diorama, parent_node_slug: rule.slug, edge_kind: "executes", kind: "effect")
      )

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Adding effect connected from Hide Clip When Playback Ends via executes")
      expect(response.body).to include(%(action="#{expected_action}"))
    end

    it "rejects invalid edge kinds" do
      get new_diorama_node_path(diorama, parent_node_slug: rule.slug, edge_kind: "teleports", kind: "effect")

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("Unsupported edge kind for child creation")
    end

    it "rejects mismatched child kinds" do
      get new_diorama_node_path(diorama, parent_node_slug: rule.slug, edge_kind: "executes", kind: "trigger")

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("Requested child kind does not match edge kind")
    end
  end

  describe "POST /dioramas/:id/nodes" do
    it "creates a child node and edge, then redirects to the new editor" do
      post diorama_nodes_path(diorama, parent_node_slug: rule.slug, edge_kind: "executes", kind: "effect"), params: {
        diorama_node_form: {
          name: "Disable Scene Item",
          description: "Child effect",
          effect: "obs.scene_item.set_enabled",
          args_scene_name: "{{ placement.sceneName }}",
          args_scene_item_id: "{{ placement.sceneItemId }}",
          enabled: "0"
        }
      }

      created = diorama.nodes.find_by!(slug: "effect.disable_scene_item_2")

      expect(response).to redirect_to(edit_diorama_node_path(diorama, created))
      expect(created.kind).to eq("effect")
      expect(created.data).to include(
        "effect" => "obs.scene_item.set_enabled"
      )
      expect(diorama.edges.find_by!(from_node: rule, to_node: created, kind: "executes")).to be_present
    end

    it "re-renders the form with errors when node validation fails" do
      expect do
        post diorama_nodes_path(diorama, parent_node_slug: rule.slug, edge_kind: "executes", kind: "effect"), params: {
          diorama_node_form: {
            name: "",
            description: "Missing name",
            effect: "obs.scene_item.set_enabled",
            args_scene_name: "{{ placement.sceneName }}",
            args_scene_item_id: "{{ placement.sceneItemId }}",
            enabled: "0"
          }
        }
      end.not_to change { DioramaEdge.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("can&#39;t be blank")
    end

    it "rejects invalid edge kinds" do
      expect do
        post diorama_nodes_path(diorama, parent_node_slug: rule.slug, edge_kind: "teleports", kind: "effect"), params: {
          diorama_node_form: {
            name: "Broken Node"
          }
        }
      end.not_to change { DioramaNode.count }

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("Unsupported edge kind for child creation")
    end

    it "rejects mismatched child kinds" do
      post diorama_nodes_path(diorama, parent_node_slug: rule.slug, edge_kind: "executes", kind: "trigger"), params: {
        diorama_node_form: {
          name: "Broken Node"
        }
      }

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("Requested child kind does not match edge kind")
    end
  end
end
