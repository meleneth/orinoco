require "json"

module Dioramas
  class JsonImporter
    attr_reader :source, :name

    def self.call(source, name: nil)
      new(source, name: name).call
    end

    def initialize(source, name: nil)
      @source = source
      @name = name
    end

    def call
      payload = parse_payload
      validate_payload!(payload)

      ActiveRecord::Base.transaction do
        diorama = create_diorama!(payload)
        node_lookup = create_nodes!(diorama, payload)
        create_edges!(diorama, payload, node_lookup)
        diorama
      end
    rescue JSON::ParserError => e
      raise ImportError, "invalid JSON: #{e.message}"
    rescue KeyError, ActiveRecord::RecordInvalid => e
      raise ImportError, e.message
    end

    private

    def parse_payload
      json = source.respond_to?(:read) ? source.read : source.to_s
      JSON.parse(json)
    end

    def validate_payload!(payload)
      raise ImportError, "import payload must be a diorama" unless payload["type"] == "diorama"
      raise ImportError, "nodes must be an array" unless payload["nodes"].is_a?(Array)
      raise ImportError, "edges must be an array" if payload["edges"].present? && !payload["edges"].is_a?(Array)
    end

    def create_diorama!(payload)
      export_name = name.presence || payload["name"].presence
      raise ImportError, "name is required" if export_name.blank?

      Diorama.create!(
        slug: Diorama.suggested_slug(export_name),
        name: export_name,
        version: payload["version"].presence || "0.1.0",
        visibility: payload["visibility"].presence || "private",
        description: payload["description"]
      )
    end

    def create_nodes!(diorama, payload)
      node_lookup = {}

      Array(payload["nodes"]).each_with_index do |node_payload, index|
        node = diorama.nodes.create!(
          slug: node_payload.fetch("slug"),
          kind: node_payload.fetch("kind"),
          name: node_payload.fetch("name"),
          description: node_payload["description"],
          data: deep_dup(node_payload["data"] || {})
        )
        node_lookup[Dioramas::JsonFormat.path_for(index)] = node
      end

      node_lookup
    end

    def create_edges!(diorama, payload, node_lookup)
      Array(payload["edges"]).each do |edge_payload|
        from_node = node_lookup.fetch(edge_payload.fetch("from"))
        to_node = node_lookup.fetch(edge_payload.fetch("to"))

        diorama.edges.create!(
          kind: edge_payload.fetch("kind"),
          from_node: from_node,
          to_node: to_node
        )
      end
    end

    def deep_dup(value)
      JSON.parse(JSON.generate(value))
    end
  end
end
