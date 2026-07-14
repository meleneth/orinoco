# frozen_string_literal: true

module Wos
  Region = Data.define(:name, :left, :top, :width, :height) do
    def crop(image)
      image.crop(left, top, width, height)
    end

    def scale_from(source_width:, source_height:, target_width:, target_height:)
      x_scale = target_width.to_f / source_width
      y_scale = target_height.to_f / source_height

      self.class.new(
        name: name,
        left: (left * x_scale).round,
        top: (top * y_scale).round,
        width: (width * x_scale).round,
        height: (height * y_scale).round
      )
    end

    def to_h
      {
        name: name,
        left: left,
        top: top,
        width: width,
        height: height
      }
    end
  end
end
