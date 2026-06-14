module Overlay
  class ElementConfig
    IDENTIFIER_REGEX = /\A[a-zA-Z0-9_-]{1,64}\z/.freeze

    attr_reader :renderer_key, :element_key, :style_preset, :content_template, :position, :size, :timer_config

    def initialize(renderer_key:, element_key:, style_preset:, content_template:, position: nil, size: nil, timer_config: nil)
      @renderer_key = renderer_key.to_s
      @element_key = element_key.to_s
      @style_preset = style_preset.to_s
      @content_template = content_template.to_s
      @position = position
      @size = size
      @timer_config = timer_config
    end

    def valid?
      validation_errors.empty?
    end

    def validate!
      return true if valid?

      raise InvalidConfigError, validation_errors.join(", ")
    end

    def validation_errors
      errors = []
      errors << "renderer_key is invalid" unless RendererRegistry.known?(renderer_key)
      errors << "element_key is invalid" unless element_key.match?(IDENTIFIER_REGEX)
      errors << "style_preset is invalid" unless StylePreset.known?(style_preset)
      errors << "content_template is too long" if content_template.length > 1_000
      errors.concat(position.validation_errors) if position.respond_to?(:validation_errors)
      errors.concat(size.validation_errors) if size.respond_to?(:validation_errors)
      errors.concat(timer_config.validation_errors) if timer_config.respond_to?(:validation_errors)
      errors
    end
  end
end
