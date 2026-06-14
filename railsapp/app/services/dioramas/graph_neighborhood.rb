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
        incoming: grouped_entries(node.incoming_edges.includes(:from_node), :from_node),
        outgoing: grouped_entries(node.outgoing_edges.includes(:to_node), :to_node)
      }
    end

    private

    attr_reader :node

    def grouped_entries(edges, linked_association)
      edges.group_by(&:kind).sort_by { |kind, _edges| kind }.to_h do |kind, grouped_edges|
        [ kind, grouped_edges.map { |edge| serialize_entry(edge, linked_association) } ]
      end
    end

    def serialize_entry(edge, linked_association)
      {
        edge: serialize_edge(edge),
        node: serialize_node(edge.public_send(linked_association))
      }
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
