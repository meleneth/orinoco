# frozen_string_literal: true

module VisualObserver
  # Converts an OBS scene-item rectangle to source-relative recognition geometry.
  # OBS item position is a scene position; it is NOT the source crop origin.
  class Calibration
    class Invalid < ArgumentError; end

    REQUIRED_FIELDS = %w[sourceWidth sourceHeight width height positionX positionY].freeze

    def self.import(scene_name:, scene_item_id:, source_name:, transform:, reference_width:, reference_height:)
      data = transform.transform_keys(&:to_s)
      width = positive(data, "sourceWidth")
      height = positive(data, "sourceHeight")
      left = nonnegative(data, "cropLeft", default: 0)
      right = nonnegative(data, "cropRight", default: 0)
      top = nonnegative(data, "cropTop", default: 0)
      bottom = nonnegative(data, "cropBottom", default: 0)
      raise Invalid, "crop exceeds source dimensions" unless left + right < width && top + bottom < height

      # Retain the exact OBS transform for rendering and calibration debugging.
      # Recognition coordinates live in the original OBS source pixel space.
      {
        "scene_name" => scene_name.to_s,
        "scene_item_id" => Integer(scene_item_id),
        "source_name" => source_name.to_s,
        "reference_width" => Integer(reference_width),
        "reference_height" => Integer(reference_height),
        "source_width" => width,
        "source_height" => height,
        "rect" => {
          "x" => left / width,
          "y" => top / height,
          "width" => (width - left - right) / width,
          "height" => (height - top - bottom) / height
        },
        "transform" => data
      }.tap do |value|
        raise Invalid, "reference dimensions must be positive" unless value["reference_width"].positive? && value["reference_height"].positive?
        raise Invalid, "scene name and source name required" if scene_name.to_s.strip.empty? || source_name.to_s.strip.empty?
      end
    rescue ArgumentError, TypeError => e
      raise Invalid, e.message
    end

    def self.positive(data, key)
      value = Float(data.fetch(key))
      raise Invalid, "#{key} must be positive and finite" unless value.finite? && value.positive?

      value
    end

    def self.nonnegative(data, key, default:)
      value = Float(data.fetch(key, default))
      raise Invalid, "#{key} must be nonnegative and finite" unless value.finite? && value >= 0

      value
    end
  end
end
