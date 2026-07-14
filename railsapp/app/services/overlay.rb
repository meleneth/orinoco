module Overlay
  class Error < StandardError; end

  class InvalidTemplateError < Error; end

  class UnknownRendererError < Error; end

  class UnknownStylePresetError < Error; end

  class InvalidConfigError < Error; end

  class UnknownLayerError < Error; end
end
