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
      Dioramas::Exporters::GraphV1.new(diorama).as_json
    end

    def to_json(*args)
      Dioramas::Exporters::GraphV1.new(diorama).to_json(*args)
    end
  end
end
