require "json"

module Dioramas
  module Importers
    class GraphV1
      attr_reader :payload, :name

      def self.call(payload, name: nil)
        new(payload, name: name).call
      end

      def initialize(payload, name: nil)
        @payload = payload
        @name = name
      end

      def call
        validate_payload!

        ActiveRecord::Base.transaction do
          diorama = create_diorama!
          nodes = create_nodes!(diorama)
          create_edges!(diorama, nodes)
          diorama
        end
      rescue KeyError, JSON::ParserError, ActiveRecord::RecordInvalid => e
        raise ImportError, e.message
      end

      private

      def validate_payload!
        raise UnsupportedSchemaVersionError, "schema_version must be 1" unless payload["schema_version"].to_s == "1"
        raise ImportError, "import payload must be a diorama" unless payload["type"] == "diorama"
        raise ImportError, "nodes must be an array" unless payload["nodes"].is_a?(Array)
        raise ImportError, "edges must be an array" unless payload["edges"].is_a?(Array)
      end

      def create_diorama!
        import_name = name.presence || payload["name"].presence
        raise ImportError, "name is required" if import_name.blank?

        Diorama.create!(
          slug: Diorama.suggested_slug(import_name),
          name: import_name,
          version: payload.fetch("version", "0.1.0"),
          visibility: payload.fetch("visibility", "private"),
          description: payload["description"]
        )
      end

      def create_nodes!(diorama)
        Array(payload["nodes"]).map do |node_payload|
          diorama.nodes.create!(
            slug: node_payload.fetch("slug"),
            kind: node_payload.fetch("kind"),
            name: node_payload.fetch("name"),
            description: node_payload["description"],
            data: deep_dup_hash(node_payload["data"])
          )
        end
      end

      def create_edges!(diorama, nodes)
        Array(payload["edges"]).each do |edge_payload|
          from_node = resolve_node_ref!(edge_payload.fetch("from"), nodes, "from")
          to_node = resolve_node_ref!(edge_payload.fetch("to"), nodes, "to")

          diorama.edges.create!(
            kind: edge_payload.fetch("kind"),
            from_node: from_node,
            to_node: to_node,
            data: deep_dup_hash(edge_payload["data"])
          )
        end
      end

      def resolve_node_ref!(ref, nodes, edge_side)
        index = Dioramas::JsonFormat.parse_node_ref(ref)
        raise InvalidNodeReferenceError, "#{edge_side} must be a $.nodes[N] reference" if index.nil?
        raise InvalidNodeReferenceError, "#{edge_side} reference #{ref.inspect} is out of range" unless index.between?(0, nodes.length - 1)

        nodes.fetch(index)
      end

      def deep_dup_hash(value)
        value.present? ? JSON.parse(JSON.generate(value)) : {}
      end
    end
  end
end
