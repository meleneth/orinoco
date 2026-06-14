module Dioramas
  module JsonFormat
    NODE_PATH_REGEX = /\A\$\.(?<array_key>nodes)\[(?<index>\d+)\]\z/.freeze
    NODE_KIND_ORDER = DioramaNode::KINDS.each_with_index.to_h.freeze

    def self.path_for(index)
      "$.nodes[#{index}]"
    end

    def self.parse_path(path)
      match = NODE_PATH_REGEX.match(path.to_s)
      return nil unless match

      {
        "array_key" => match[:array_key],
        "index" => match[:index].to_i
      }
    end

    def self.order_key_for(node)
      [ NODE_KIND_ORDER.fetch(node.kind, NODE_KIND_ORDER.length), node.slug.to_s, node.name.to_s ]
    end
  end
end
