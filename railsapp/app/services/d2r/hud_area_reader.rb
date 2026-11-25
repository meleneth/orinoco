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
      # Include the game name, area and optional difficulty row.
      height = (image.height * 0.11).round.clamp(1, image.height)
      roi = image.crop(left, 0, width, height).resize(2.0)
      Tempfile.create([ "d2r-area-", ".png" ]) do |file|
        roi.write_to_file(file.path)
        output, status = Open3.capture2(
          "tesseract", file.path, "stdout", "-l", "eng", "--psm", "6",
          err: File::NULL
        )
        return {} unless status.success?

        self.class.read_hud(output)
      end
    rescue Vips::Error, Errno::ENOENT => e
      Rails.logger.warn("[d2r-hud-area] #{e.class}: #{e.message}") if defined?(Rails)
      {}
    end

    def self.read_hud(value)
      lines = value.to_s.lines.filter_map do |line|
        normalized = normalize_text(line)
        normalized unless normalized.empty?
      end
      game_named = lines.first&.match?(/\bgame [a-z0-9]+/)
      area = parse_heading(game_named ? lines[1] : lines.first)
      difficulty = lines.drop(game_named ? 2 : 1).filter_map do |line|
        label = line[/\b(?:nightmare|hell)\z/]
        label.capitalize if label && (line == label || line.match?(/\bdiffic\w* /))
      end.first
      { "area" => area, "difficulty" => difficulty, "game_named" => !!game_named }.compact
    end

    def self.parse(value)
      read_hud(value)["area"]
    end

    def self.parse_heading(heading)
      return nil unless heading

      # Prefer longest names so a complete 'Level 5' cannot match a shorter
      # prefix of the same label.
      areas = AREA_NAMES.sort_by { |area| -area.length }
      exact = areas.find do |area|
        target = normalize_text(area)
        heading.include?(target)
      end
      return exact if exact

      matches = areas.filter_map do |area|
        target = normalize_text(area)
        candidate = best_token_window(heading, target)
        next unless candidate

        distance = edit_distance(ocr_signature(candidate), ocr_signature(target))
        limit = [ 1, (ocr_signature(target).length * 0.18).ceil ].max
        [ area, distance ] if distance <= limit
      end
      best, runner_up = matches.sort_by { |(_, distance)| distance }.first(2)
      return nil if best && runner_up && best.last == runner_up.last && best.first != runner_up.first

      best&.first
    end

    def self.normalize_text(value)
      value.to_s.downcase.tr("@®", "oo").gsub(/[^a-z0-9]+/, " ").strip.gsub(/\s+/, " ")
    end

    def self.best_token_window(heading, target)
      words = heading.split
      target_words = target.split.length
      windows = ((target_words - 1).clamp(1, target_words)..(target_words + 1)).flat_map do |length|
        words.each_cons(length).map { |parts| parts.join(" ") }
      end
      windows.min_by { |candidate| edit_distance(ocr_signature(candidate), ocr_signature(target)) }
    end

    # Exocet's round glyphs are frequently interchanged by OCR (for example,
    # "Blood Moor" becomes "BLe@eo Meer"). A vowel-family signature keeps the
    # known-area match strict on consonants while tolerating those substitutions.
    def self.ocr_signature(value)
      normalize_text(value).tr("aeiou0", "vvvvvv").gsub(/v+/, "v")
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
