# frozen_string_literal: true

require "open3"
require "tempfile"
require "vips"
require_relative "character_sheet_reader"

module D2r
  # Reads the selected character summary from the roster and create-game
  # screens. Both surfaces repeat the canonical name/level/class line, making
  # them a safer identity boundary than inferring a character from gameplay.
  class CharacterMenuReader
    REGIONS = {
      "character_select" => [ 0.79, 0.075, 0.17, 0.075 ],
      "game_creation" => [ 0.41, 0.59, 0.18, 0.065 ]
    }.freeze

    def call(path, screen:)
      rect = REGIONS[screen.to_s]
      return {} unless rect

      image = Vips::Image.new_from_file(path.to_s, access: :random)
      reading = CharacterSheetReader.parse_identity(ocr(crop(image, rect)))
      return reading if screen != "game_creation" || %w[name character_class level].all? { |key| reading[key] }

      # The lobby's name and level/class are separate, tightly spaced rows.
      name = ocr(crop(image, [ 0.4492, 0.6000, 0.1035, 0.0234 ]), psm: 7).strip
      summary = ocr(crop(image, [ 0.4395, 0.621875, 0.1221, 0.01875 ]), psm: 7, contrast: true)
      summary = summary.sub(/\bLev(?:er|en|et)\b/i, "Level")
      fallback = CharacterSheetReader.parse_identity("#{name}\n#{summary}")
      reading.merge(fallback)

    rescue Vips::Error, Errno::ENOENT
      {}
    end

    private

    def crop(image, rect)
      left = (image.width * rect.fetch(0)).round.clamp(0, image.width - 1)
      top = (image.height * rect.fetch(1)).round.clamp(0, image.height - 1)
      width = (image.width * rect.fetch(2)).round.clamp(1, image.width - left)
      height = (image.height * rect.fetch(3)).round.clamp(1, image.height - top)
      image.crop(left, top, width, height)
    end

    def ocr(image, psm: 6, contrast: false)
      Tempfile.create([ "d2r-character-menu-", ".png" ]) do |file|
        prepared = image.colourspace("b-w").resize(4.0)
        if contrast
          low, high = prepared.min, prepared.max
          return "" unless high > low

          prepared = ((prepared - low) * (-255.0 / (high - low)) + 255).cast("uchar")
          prepared = prepared.embed(15, 15, prepared.width + 30, prepared.height + 30, extend: :background, background: [255])
        else
          prepared = prepared.sharpen
        end
        prepared.write_to_file(file.path)
        output, status = Open3.capture2(
          "tesseract", file.path, "stdout", "-l", "eng", "--psm", psm.to_s,
          err: File::NULL
        )
        status.success? ? output : ""
      end
    rescue Errno::ENOENT
      ""
    end
  end
end
