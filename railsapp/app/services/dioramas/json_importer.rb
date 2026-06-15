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
      raise ImportError, "import payload must be an object" unless payload.is_a?(Hash)

      case payload["schema_version"].to_s
      when "1"
        Dioramas::Importers::GraphV1.call(payload, name: name)
      when ""
        raise UnsupportedSchemaVersionError, "schema_version is required"
      else
        raise UnsupportedSchemaVersionError, "unsupported schema_version #{payload['schema_version'].inspect}"
      end
    rescue JSON::ParserError => e
      raise ImportError, "invalid JSON: #{e.message}"
    end

    private

    def parse_payload
      json = source.respond_to?(:read) ? source.read : source.to_s
      JSON.parse(json)
    end
  end
end
