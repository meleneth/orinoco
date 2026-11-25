# frozen_string_literal: true

module D2r
  module OcrTextMask
    # Pass dark glyphs on a white background to Tesseract.
    def self.white(image)
      red, green, blue = image.colourspace("srgb").bandsplit
      pixels = (red >= 155) & (green >= 155) & (blue >= 155) &
        ((red - green).abs <= 24) & ((green - blue).abs <= 24)
      pixels.invert
    end

    def self.gold(image)
      red, green, blue = image.colourspace("srgb").bandsplit
      pixels = (red >= 115) & (green >= 100) & (red >= green) & (red <= green * 1.35) &
        (green > blue * 1.18) & (green < blue * 2.4)
      pixels.invert
    end
  end
end
