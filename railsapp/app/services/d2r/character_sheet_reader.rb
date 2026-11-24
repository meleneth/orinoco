# frozen_string_literal: true

require "open3"
require "tempfile"
require "vips"

module D2r
  # Conservative label-based OCR. Never fill missing values from guesses.
  # Actual character-sheet OCR accuracy still needs fixture verification.
  class CharacterSheetReader
    CLASSES = %w[Amazon Assassin Barbarian Druid Necromancer Paladin Sorceress Warlock].freeze
    STATS = %w[Strength Dexterity Vitality Energy].freeze

    def call(path)
      image = Vips::Image.new_from_file(path.to_s)
      roi = image.crop(0, 0, (image.width * 0.49).round, (image.height * 0.86).round)
      Tempfile.create(["d2r-character-", ".png"]) do |file|
        roi.resize(2.0).write_to_file(file.path)
        output, status = Open3.capture2("tesseract", file.path, "stdout", "-l", "eng", "--psm", "6", err: File::NULL)
        status.success? ? self.class.parse(output) : {}
      end
    rescue Vips::Error, Errno::ENOENT
      {}
    end

    def self.parse(text)
      result = {}
      lines = text.to_s.lines.map(&:strip).reject(&:empty?)
      class_pattern = CLASSES.join("|")
      lines.each_with_index do |line, index|
        if (match = line.match(/\bLevel\s+(\d{1,2})\s+(#{class_pattern})\b/i))
          level = match[1].to_i
          next unless (1..99).cover?(level)
          result["level"] = level
          result["character_class"] = CLASSES.find { |klass| klass.casecmp?(match[2]) }
          candidate = lines[index - 1] if index.positive?
          result["name"] = candidate if candidate&.match?(/\A[A-Za-z][A-Za-z_-]{1,14}\z/)
        end
        if (match = line.match(/\A(?:Current\s+)?Experience\s*[: ]\s*([\d,]+)\s*\z/i))
          result["experience"] = match[1].delete(",").to_i
        end
        STATS.each do |stat|
          match = line.match(/\A#{stat}\s*[: ]\s*(\d+)\s*\z/i)
          (result["stats"] ||= {})[stat.downcase] = match[1].to_i if match
        end
      end
      result
    end
  end
end
