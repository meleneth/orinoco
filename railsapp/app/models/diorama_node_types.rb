module DioramaNodeTypes
  def self.wrap(node)
    case node.kind
    when "asset"
      Asset.new(node)
    when "effect"
      Effect.new(node)
    else
      Unknown.new(node)
    end
  end

  class Base
    attr_reader :node

    def initialize(node)
      @node = node
    end

    def data
      node.data || {}
    end

    def kind
      node.kind
    end

    def slug
      node.slug
    end

    def name
      node.name
    end

    def validate_data
      []
    end
  end

  class Unknown < Base
  end

  class Asset < Base
    def image_value
      return nil unless data["asset_type"] == "image"
      image = data["image"] || data["image_value"]
      return nil unless image.is_a?(Hash)

      DioramaImageValue.new(image)
    end

    def validate_data
      image = image_value
      return [] unless image

      image.validation_errors.map { |error| "image #{error}" }
    end
  end

  class Effect < Base
    def validate_data
      return [] if data["effect"].present?

      ["effect is required"]
    end
  end
end
