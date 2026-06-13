module Dioramas
  class GraphNeighborhood
    def self.call(node)
      new(node).call
    end

    def initialize(node)
      @node = node
    end

    def call
      {
        current: serialize_node(node),
        incoming: incoming_entries,
        outgoing: outgoing_entries
      }
    end

    private

    attr_reader :node

    def incoming_entries
      node.incoming_edges.includes(:from_node).map do |edge|
        {
          edge: serialize_edge(edge),
          node: serialize_node(edge.from_node)
        }
      end
    end

    def outgoing_entries
      node.outgoing_edges.includes(:to_node).map do |edge|
        {
          edge: serialize_edge(edge),
          node: serialize_node(edge.to_node)
        }
      end
    end

    def serialize_node(target)
      {
        id: target.id,
        slug: target.slug,
        kind: target.kind,
        name: target.name,
        description: target.description,
        data: target.data,
        validation_state: target.validation_state
      }
    end

    def serialize_edge(edge)
      {
        id: edge.id,
        kind: edge.kind,
        from_node_id: edge.from_node_id,
        to_node_id: edge.to_node_id,
        data: edge.data
      }
    end
  end
end
