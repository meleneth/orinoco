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
      "Rogue Encampment", "Lut Gholein", "Kurast Docks", "Pandemonium Fortress", "Harrogath", "Black Marsh", "Forgotten Tower",
      *(1..5).map { |level| "Tower Cellar Level #{level}" },
      "Catacombs Level 2", "Catacombs Level 3", "Catacombs Level 4",
      "Durance of Hate Level 2", "Durance of Hate Level 3",
      "River of Flame", "Chaos Sanctuary",
      "Worldstone Keep Level 2", "Worldstone Keep Level 3",
      "Throne of Destruction", "Worldstone Chamber",
      "Moo Moo Farm", "Travincal", "Blood Moor", "Den of Evil", "Cold Plains", "Stony Field",
      "Dark Wood", "Tristram", "Canyon of the Magi", "Tal Rasha\u0027s Tomb", "Tal Rasha\u0027s Chamber",
      "Sewers Level 1", "Sewers Level 2", "Sewers Level 3", "Rocky Waste", "Dry Hills", "Far Oasis",
      "Lost City", "Valley of Snakes", "Arcane Sanctuary", "Spider Forest", "Great Marsh", "Flayer Jungle",
      "Lower Kurast", "Kurast Bazaar", "Upper Kurast", "Outer Steppes", "Plains of Despair",
      "City of the Damned", "Bloody Foothills", "Frigid Highlands", "Arreat Summit"
    ].freeze

    def call(path)
      image = Vips::Image.new_from_file(path.to_s)
      left = (image.width * 0.79).round.clamp(0, image.width - 1)
      width = image.width - left
      # Only the first physical HUD line is the current area. Cropping the
      # larger text block lets difficulty modifiers or terror-zone names move
      # into the first OCR line whenever the area heading is absent.
      height = (image.height * 0.05).round.clamp(1, image.height)
      roi = image.crop(left, 0, width, height).resize(2.0)
      Tempfile.create([ "d2r-area-", ".png" ]) do |file|
        roi.write_to_file(file.path)
        output, status = Open3.capture2(
          "tesseract", file.path, "stdout", "-l", "eng", "--psm", "7",
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
      lines = value.to_s.lines.filter_map do |line|
        normalized = normalize_text(line)
        normalized unless normalized.empty?
      end
      return nil if lines.empty?

      # The area heading is the first OCR line. Later lines contain difficulty,
      # monster modifiers, and terror-zone names; considering those as area
      # candidates can turn the terror-zone list into a false area change.
      heading = lines.first

      # Prefer longest names so a complete 'Level 5' cannot match a shorter
      # prefix of the same label.
      areas = AREA_NAMES.sort_by { |area| -area.length }
      exact = areas.find do |area|
        target = normalize_text(area)
        heading.include?(target)
      end
      return exact if exact

      areas.filter_map do |area|
        target = normalize_text(area)
        next if (heading.length - target.length).abs > 3

        distance = edit_distance(heading, target)
        next unless distance <= [ 1, (target.length * 0.12).ceil ].max

        [ area, distance ]
      end.min_by(&:last)&.first
    end

    def self.normalize_text(value)
      value.to_s.downcase.tr("@®", "oo").gsub(/[^a-z0-9]+/, " ").strip.gsub(/\s+/, " ")
    end

    def self.edit_distance(left, right)
      previous = (0..right.length).to_a
      left.each_char.with_index(1) do |left_char, row|
        current = [ row ]
        right.each_char.with_index(1) do |right_char, column|
          current[column] = [
            current[column - 1] + 1,
            previous[column] + 1,
            previous[column - 1] + (left_char == right_char ? 0 : 1)
          ].min
        end
        previous = current
      end
      previous.last
    end
  end
end
