require "json"

module Dioramas
  module Exporters
    class GraphV1
      attr_reader :diorama

      def initialize(diorama)
        @diorama = diorama
      end

      def as_json
        base_payload.merge(
          "nodes" => node_payloads,
          "edges" => edge_payloads
        )
      end

      def to_json(*)
        JSON.pretty_generate(as_json)
      end

      private

      def base_payload
        {
          "type" => "diorama",
          "schema_version" => "1",
          "name" => diorama.name,
          "slug" => diorama.slug,
          "version" => diorama.version,
          "visibility" => diorama.visibility,
          "description" => diorama.description
        }.compact
      end

      def node_payloads
        ordered_nodes.map do |node|
          payload = {
            "kind" => node.kind,
            "slug" => node.slug,
            "name" => node.name,
            "data" => deep_dup_hash(node.data)
          }
          payload["description"] = node.description if node.description.present?
          payload
        end
      end

      def edge_payloads
        edge_positions = build_edge_positions

        diorama.edges.includes(:from_node, :to_node).sort_by do |edge|
          [
            edge_positions.fetch(edge.from_node_id),
            edge_positions.fetch(edge.to_node_id),
            edge.kind.to_s,
            canonical_edge_data(edge.data)
          ]
        end.map do |edge|
          {
            "kind" => edge.kind,
            "from" => Dioramas::JsonFormat.path_for(edge_positions.fetch(edge.from_node_id)),
            "to" => Dioramas::JsonFormat.path_for(edge_positions.fetch(edge.to_node_id)),
            "data" => deep_dup_hash(edge.data)
          }
        end
      end

      def build_edge_positions
        positions = {}

        ordered_nodes.each_with_index do |node, index|
          positions[node.id] = index
        end

        positions
      end

      def ordered_nodes
        @ordered_nodes ||= diorama.nodes.sort_by { |node| Dioramas::JsonFormat.order_key_for(node) }
      end

      def deep_dup_hash(value)
        value.present? ? JSON.parse(JSON.generate(value)) : {}
      end

      def canonical_edge_data(value)
        JSON.generate(deep_dup_hash(value))
      end
    end
  end
end
