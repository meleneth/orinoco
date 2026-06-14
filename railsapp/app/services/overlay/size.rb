module Overlay
  class Size
    UNITS = %w[px percent auto].freeze

    attr_reader :width, :height, :size_unit

    def initialize(width:, height:, size_unit:)
      @width = width
      @height = height
      @size_unit = size_unit.to_s
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
      errors << "size_unit is invalid" unless UNITS.include?(size_unit)
      errors << "width must be a number" if width.present? && !numeric?(width) && size_unit != "auto"
      errors << "height must be a number" if height.present? && !numeric?(height) && size_unit != "auto"
      errors
    end

    def css_declarations
      validate!

      return "" if size_unit == "auto"

      declarations = []
      declarations << "width:#{format_value(width)};" if width.present?
      declarations << "height:#{format_value(height)};" if height.present?
      declarations.join
    end

    private

    def numeric?(value)
      Float(value)
      true
    rescue ArgumentError, TypeError
      false
    end

    def format_value(value)
      numeric = Float(value)
      size_unit == "percent" ? "#{numeric}%" : "#{numeric.to_i == numeric ? numeric.to_i : numeric}px"
    end
  end
end
