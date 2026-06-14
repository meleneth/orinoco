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
      base_payload.merge(node_payloads).merge("edges" => edge_payloads)
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
      Dioramas::JsonFormat.array_keys.each_with_object({}) do |array_key, payload|
        payload[array_key] = nodes_for(array_key)
      end
    end

    def nodes_for(array_key)
      kind = Dioramas::JsonFormat.kind_for(array_key)

      diorama.nodes.where(kind: kind).order(:slug).map do |node|
        serialize_node(node)
      end
    end

    def serialize_node(node)
      {
        "slug" => node.slug,
        "name" => node.name,
        "description" => node.description,
        "data" => node.data || {}
      }.compact
    end

    def edge_payloads
      edge_paths = build_edge_paths

      diorama.edges.includes(:from_node, :to_node).order(:id).map do |edge|
        {
          "kind" => edge.kind,
          "from" => edge_paths.fetch(edge.from_node_id),
          "to" => edge_paths.fetch(edge.to_node_id)
        }
      end
    end

    def build_edge_paths
      paths = {}

      Dioramas::JsonFormat.array_keys.each do |array_key|
        kind = Dioramas::JsonFormat.kind_for(array_key)
        diorama.nodes.where(kind: kind).order(:slug).each_with_index do |node, index|
          paths[node.id] = Dioramas::JsonFormat.path_for(array_key, index)
        end
      end

      paths
    end
  end
end
