# frozen_string_literal: true

require "open3"
require "tempfile"
require "vips"

module D2r
  # Fallback for areas missing from the hand-captured bitmap reference set.
  # Tesseract is not a replacement for confirmed Exocet fixtures; the parser
  # only accepts known game areas and HudTracker still requires two frames.
  class HudAreaReader
    AREA_NAMES = [
      "Rogue Encampment", "Black Marsh", "Forgotten Tower",
      *(1..5).map { |level| "Tower Cellar Level #{level}" },
      "Catacombs Level 2", "Catacombs Level 3", "Catacombs Level 4",
      "Durance of Hate Level 2", "Durance of Hate Level 3",
      "River of Flame", "Chaos Sanctuary",
      "Worldstone Keep Level 2", "Worldstone Keep Level 3",
      "Throne of Destruction", "Worldstone Chamber",
      "Moo Moo Farm", "Travincal"
    ].freeze

    def call(path)
      image = Vips::Image.new_from_file(path.to_s)
      left = (image.width * 0.79).round.clamp(0, image.width - 1)
      width = image.width - left
      height = (image.height * 0.16).round.clamp(1, image.height)
      roi = image.crop(left, 0, width, height).resize(2.0)
      Tempfile.create(["d2r-area-", ".png"]) do |file|
        roi.write_to_file(file.path)
        output, status = Open3.capture2(
          "tesseract", file.path, "stdout", "-l", "eng", "--psm", "6",
          err: File::NULL
        )
        return nil unless status.success?

        self.class.parse(output)
      end
    rescue Vips::Error, Errno::ENOENT => e
      Rails.logger.warn("[d2r-hud-area] #{e.class}: #{e.message}") if defined?(Rails)
      nil
    end

    def self.parse(value)
      text = value.to_s.gsub(/\s+/, " ").strip.downcase
      return nil if text.empty?

      # Prefer longest names so a complete 'Level 5' cannot match a shorter
      # prefix of the same label.
      AREA_NAMES.sort_by { |area| -area.length }.find do |area|
        text.include?(area.downcase)
      end
    end
  end
end
