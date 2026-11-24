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
      CharacterSheetReader.parse_identity(ocr(crop(image, rect)))
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

    def ocr(image)
      Tempfile.create([ "d2r-character-menu-", ".png" ]) do |file|
        image.colourspace("b-w").resize(4.0).sharpen.write_to_file(file.path)
        output, status = Open3.capture2(
          "tesseract", file.path, "stdout", "-l", "eng", "--psm", "6",
          err: File::NULL
        )
        status.success? ? output : ""
      end
    rescue Errno::ENOENT
      ""
    end
  end
end
