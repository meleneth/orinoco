module Dioramas
  module EdgeKinds
    CHILD_KIND_BY_EDGE_KIND = {
      "uses" => "trigger",
      "selects" => "selector",
      "guards" => "condition",
      "executes" => "effect",
      "provides" => "asset",
      "places" => "placement",
      "binds" => "binding",
      "falls_back_to" => "fallback"
    }.freeze

    RELEVANT_OUTGOING_EDGE_KINDS_BY_NODE_KIND = {
      "affordance" => [ "contains" ],
      "rule" => [ "uses", "selects", "guards", "executes" ]
    }.freeze

    def self.child_kind_for(edge_kind, parent_kind: nil)
      return "rule" if edge_kind.to_s == "contains" && parent_kind.to_s == "affordance"

      CHILD_KIND_BY_EDGE_KIND[edge_kind.to_s]
    end

    def self.creatable_outgoing_edge_kinds_for(node_or_kind)
      node_kind = node_or_kind.respond_to?(:kind) ? node_or_kind.kind : node_or_kind.to_s
      RELEVANT_OUTGOING_EDGE_KINDS_BY_NODE_KIND.fetch(node_kind, [])
    end

    def self.add_label_for(edge_kind)
      case edge_kind.to_s
      when "contains"
        "Add rule"
      else
        child_kind = child_kind_for(edge_kind)
        child_kind ? "Add #{child_kind}" : nil
      end
    end
  end
end
