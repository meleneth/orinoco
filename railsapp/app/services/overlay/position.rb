module Overlay
  class Position
    ANCHORS = %w[
      top_left
      top_right
      bottom_left
      bottom_right
      center
    ].freeze

    UNITS = %w[px percent].freeze

    attr_reader :anchor, :x, :y, :unit

    def initialize(anchor:, x:, y:, unit:)
      @anchor = anchor.to_s
      @x = x
      @y = y
      @unit = unit.to_s
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
      errors << "anchor is invalid" unless ANCHORS.include?(anchor)
      errors << "unit is invalid" unless UNITS.include?(unit)
      errors << "x must be a number" unless numeric?(x)
      errors << "y must be a number" unless numeric?(y)
      errors
    end

    def css_declarations
      validate!

      case anchor
      when "top_left"
        "position:absolute;left:#{format_value(x)};top:#{format_value(y)};"
      when "top_right"
        "position:absolute;right:#{format_value(x)};top:#{format_value(y)};"
      when "bottom_left"
        "position:absolute;left:#{format_value(x)};bottom:#{format_value(y)};"
      when "bottom_right"
        "position:absolute;right:#{format_value(x)};bottom:#{format_value(y)};"
      when "center"
        "position:absolute;left:calc(50% + #{format_value(x)});top:calc(50% + #{format_value(y)});transform:translate(-50%, -50%);"
      end
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
      unit == "percent" ? "#{numeric}%" : "#{numeric.to_i == numeric ? numeric.to_i : numeric}px"
    end
  end
end
