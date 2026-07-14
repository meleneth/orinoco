# frozen_string_literal: true

require "time"

module Orinoco
  module Pipeline
    class Event
      class Invalid < StandardError; end

      attr_reader :type, :source, :occurred_at, :payload, :correlation, :raw

      def initialize(type:, payload:, source: nil, occurred_at: nil, correlation: {}, raw: nil)
        @type = require_string(type, "type")
        @source = source || infer_source(@type)
        @occurred_at = occurred_at || Time.now.utc.iso8601
        @payload = payload || {}
        @correlation = correlation || {}
        @raw = raw || to_h
      end

      def self.from_hash(hash)
        raise Invalid, "event envelope must be a hash" unless hash.is_a?(Hash)

        data = stringify_keys(hash)
        new(
          type: data.fetch("type"),
          source: data["source"],
          occurred_at: data["occurred_at"],
          payload: data.fetch("payload", {}),
          correlation: data.fetch("correlation", {}),
          raw: data
        )
      rescue KeyError => e
        raise Invalid, "event envelope missing #{e.key}"
      end

      def self.build(type, payload = {}, source: nil, correlation: {}, occurred_at: nil)
        new(type: type, payload: payload, source: source, correlation: correlation, occurred_at: occurred_at)
      end

      def to_h
        {
          "type" => type,
          "source" => source,
          "occurred_at" => occurred_at,
          "payload" => payload,
          "correlation" => correlation
        }
      end

      def [](key)
        payload.fetch(key.to_s)
      end

      def payload_value(key, default = nil)
        payload.fetch(key.to_s, default)
      end

      def handled?
        @handled == true
      end

      def handled!
        @handled = true
      end

      def self.stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, inner_value), result|
            result[key.to_s] = stringify_keys(inner_value)
          end
        when Array
          value.map { |entry| stringify_keys(entry) }
        else
          value
        end
      end

      def require_string(value, field_name)
        string = value.to_s
        raise Invalid, "#{field_name} must be present" if string.strip.empty?

        string
      end

      def infer_source(event_type)
        source = event_type.to_s.split(".").first(2).join(".")
        source.empty? ? "orinoco" : source
      end
    end
  end
end