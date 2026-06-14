module Dioramas
  module JsonFormat
    NODE_ARRAY_BY_KIND = {
      "affordance" => "affordances",
      "rule" => "rules",
      "trigger" => "triggers",
      "selector" => "selectors",
      "condition" => "conditions",
      "effect" => "effects",
      "asset" => "assets",
      "placement" => "placements",
      "binding" => "bindings",
      "fallback" => "fallbacks",
      "capability" => "capabilities",
      "test_event" => "test_events",
      "runtime_trace" => "runtime_traces"
    }.freeze

    NODE_KIND_BY_ARRAY = NODE_ARRAY_BY_KIND.invert.freeze
    NODE_ARRAY_KEYS = NODE_ARRAY_BY_KIND.values.freeze

    PATH_REGEX = /\A\$\.(?<array_key>[a-z_]+)\[(?<index>\d+)\]\z/.freeze

    def self.array_key_for(kind)
      NODE_ARRAY_BY_KIND.fetch(kind.to_s)
    end

    def self.kind_for(array_key)
      NODE_KIND_BY_ARRAY.fetch(array_key.to_s)
    end

    def self.array_keys
      NODE_ARRAY_KEYS
    end

    def self.path_for(array_key, index)
      "$.#{array_key}[#{index}]"
    end

    def self.parse_path(path)
      match = PATH_REGEX.match(path.to_s)
      return nil unless match

      {
        "array_key" => match[:array_key],
        "index" => match[:index].to_i
      }
    end
  end
end
