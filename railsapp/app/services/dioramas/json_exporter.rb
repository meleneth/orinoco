require "json"

module Dioramas
  class JsonExporter
    attr_reader :diorama

    def self.call(diorama)
      new(diorama).as_json
    end

    def initialize(diorama)
      @diorama = diorama
    end

    def as_json
      base_payload.merge("nodes" => node_payloads, "edges" => edge_payloads)
    end

    def to_json(*args)
      JSON.pretty_generate(as_json)
    end

    private

    def base_payload
      {
        "type" => "diorama",
        "name" => diorama.name,
        "slug" => diorama.slug,
        "version" => diorama.version,
        "visibility" => diorama.visibility,
        "description" => diorama.description
      }.compact
    end

    def node_payloads
      ordered_nodes.map do |node|
        serialize_node(node)
      end
    end

    def serialize_node(node)
      {
        "kind" => node.kind,
        "slug" => node.slug,
        "name" => node.name,
        "description" => node.description,
        "data" => node.data || {}
      }.compact
    end

    def edge_payloads
      edge_paths = build_edge_paths

      diorama.edges.includes(:from_node, :to_node).sort_by do |edge|
        [ edge_paths.fetch(edge.from_node_id), edge_paths.fetch(edge.to_node_id), edge.kind.to_s ]
      end.map do |edge|
        {
          "kind" => edge.kind,
          "from" => edge_paths.fetch(edge.from_node_id),
          "to" => edge_paths.fetch(edge.to_node_id)
        }
      end
    end

    def build_edge_paths
      paths = {}

      ordered_nodes.each_with_index do |node, index|
        paths[node.id] = Dioramas::JsonFormat.path_for(index)
      end

      paths
    end

    def ordered_nodes
      @ordered_nodes ||= diorama.nodes.sort_by { |node| Dioramas::JsonFormat.order_key_for(node) }
    end
  end
end
