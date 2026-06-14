module Overlay
  module RendererRegistry
    REGISTRY = {
      "text_box" => Overlay::Renderers::TextBox,
      "timer_text" => Overlay::Renderers::TimerText
    }.freeze

    def self.fetch!(key)
      REGISTRY.fetch(key.to_s) do
        raise UnknownRendererError, "unknown renderer #{key.inspect}"
      end
    end

    def self.known?(key)
      REGISTRY.key?(key.to_s)
    end

    def self.keys
      REGISTRY.keys
    end
  end
end
