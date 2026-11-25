# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "tempfile"
require "vips"

module D2r
  # Reads small, normalized regions independently. A failed field never erases
  # another successful field, and unchanged panels reuse their prior OCR.
  class CharacterSheetReader
    CLASSES = %w[Amazon Assassin Barbarian Druid Necromancer Paladin Sorceress].freeze
    PANEL = [ 0.055, 0.09, 0.36, 0.70 ].freeze
    REGIONS = {
      identity: [ 0.08, 0.16, 0.30, 0.09 ],
      name: [ 0.101, 0.17, 0.22, 0.027 ],
      experience: [ 0.08, 0.205, 0.30, 0.07 ],
      primary_attributes: [ 0.08, 0.265, 0.14, 0.38 ],
      resources: [ 0.22, 0.25, 0.17, 0.40 ],
      resistances: [ 0.08, 0.64, 0.31, 0.10 ],
      unspent_points: [ 0.08, 0.73, 0.30, 0.055 ]
    }.freeze
    PRIMARY_STATS = %w[strength dexterity vitality energy].freeze
    RESOURCE_STATS = %w[life mana stamina].freeze
    RESISTANCE_STATS = %w[fire cold lightning poison].freeze

    def initialize
      @cached_fingerprint = nil
      @cached_reading = {}
    end

    def call(path)
      image = Vips::Image.new_from_file(path.to_s, access: :random)
      panel = crop(image, PANEL)
      fingerprint = Digest::SHA256.hexdigest(panel.write_to_memory)
      return deep_copy(@cached_reading) if fingerprint == @cached_fingerprint

      reading = {}
      identity_text = ocr(crop(image, REGIONS.fetch(:identity)), psm: 6)
      merge_identity(reading, identity_text)
      if reading["level"] && !reading["name"]
        name = self.class.clean(self.class.normalize_letters(ocr(crop(image, REGIONS.fetch(:name)), psm: 7)))
        reading["name"] = name if self.class.valid_name?(name)
      end
      # D2R renders the compact "current of next" XP values on the same row
      # as level and class. Parse that high-signal crop before the looser
      # fallback region used by other layouts.
      merge_experience(reading, identity_text)
      merge_experience(reading, ocr(crop(image, REGIONS.fetch(:experience)), psm: 6))
      merge_stats(reading, ocr(crop(image, REGIONS.fetch(:primary_attributes)), psm: 6), PRIMARY_STATS)
      merge_stats(reading, ocr(crop(image, REGIONS.fetch(:resources)), psm: 6), RESOURCE_STATS)
      merge_resistances(reading, ocr(crop(image, REGIONS.fetch(:resistances)), psm: 6))
      merge_unspent(reading, ocr(crop(image, REGIONS.fetch(:unspent_points)), psm: 7))
      @cached_fingerprint = fingerprint
      @cached_reading = reading
      deep_copy(reading)
    rescue Vips::Error, Errno::ENOENT
      {}
    end

    def self.parse_identity(text)
      lines = text.to_s.lines.map { |line| clean(normalize_letters(line)) }.reject(&:empty?)
      result = {}
      class_pattern = CLASSES.join("|")
      lines.each_with_index do |line, index|
        match = line.match(/\bLevel\s+([\d|Il]{1,2})\s+(#{class_pattern})\b/i) ||
          line.match(/\b(#{class_pattern})\s+Level\s+([\d|Il]{1,2})\b/i)
        next unless match

        if match[1].match?(/\A[\d|Il]/)
          level, character_class = normalize_number(match[1]), match[2]
        else
          character_class, level = match[1], normalize_number(match[2])
        end
        next unless (1..99).cover?(level)

        result["level"] = level
        result["character_class"] = CLASSES.find { |klass| klass.casecmp?(character_class) }
        candidate = lines[index - 1] if index.positive?
        result["name"] = candidate if valid_name?(candidate)
      end
      result
    end

    def self.parse_experience(text)
      result = {}
      normalized = text.to_s.gsub(",", "")
        .gsub(/(?<![A-Za-z])[@O](?![A-Za-z])/i, "0")
      if (match = normalized.match(/(?:Current\s+)?Experience\D+(\d{1,12})/i))
        result["experience"] = match[1].to_i
      end
      if (match = normalized.match(/(?:Next\s+Level|Experience\s+Required)\D+(\d{1,12})/i))
        result["experience_next_level"] = match[1].to_i
      end
      if (match = normalized.match(/(\d{1,12})\s+of\s+(\d{1,12})/i))
        result["experience"] ||= match[1].to_i
        result["experience_next_level"] ||= match[2].to_i
      end
      result
    end

    def self.parse_named_numbers(text, names)
      normalized = text.to_s.gsub(/(?<![A-Za-z])[@O©](?=\s*%)/i, "0")
      names.to_h do |name|
        label = name.tr("_", " ")
        match = normalized.match(/\b#{Regexp.escape(label)}\b\D{0,12}(-?\d{1,7})/i)
        [ name, match && match[1].to_i ]
      end.compact
    end

    def self.clean(value)
      value.to_s.gsub(/[^A-Za-z0-9_| -]/, " ").strip.gsub(/\s+/, " ")
    end

    def self.valid_name?(value)
      value&.match?(/\A[A-Za-z][A-Za-z_-]{1,14}\z/)
    end

    def self.normalize_letters(value)
      value.to_s.gsub(/(?<=[A-Za-z])[@®0](?=[A-Za-z])/i, "o")
    end

    def self.normalize_number(value)
      value.to_s.tr("|Il", "111").to_i
    end

    private

    def crop(image, rect)
      left = (image.width * rect.fetch(0)).round.clamp(0, image.width - 1)
      top = (image.height * rect.fetch(1)).round.clamp(0, image.height - 1)
      width = (image.width * rect.fetch(2)).round.clamp(1, image.width - left)
      height = (image.height * rect.fetch(3)).round.clamp(1, image.height - top)
      image.crop(left, top, width, height)
    end

    def ocr(image, psm:)
      Tempfile.create([ "d2r-character-field-", ".png" ]) do |file|
        prepared = image.resize([ 4.0, 900.0 / image.height ].min).sharpen
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

    def merge_identity(reading, text)
      reading.merge!(self.class.parse_identity(text))
    end

    def merge_experience(reading, text)
      reading.merge!(self.class.parse_experience(text))
    end

    def merge_stats(reading, text, names)
      values = self.class.parse_named_numbers(text, names)
      reading["stats"] = reading.fetch("stats", {}).merge(values) if values.any?
    end

    def merge_resistances(reading, text)
      values = self.class.parse_named_numbers(text, RESISTANCE_STATS).transform_keys { |name| "#{name}_resistance" }
      reading["stats"] = reading.fetch("stats", {}).merge(values) if values.any?
    end

    def merge_unspent(reading, text)
      match = text.to_s.match(/(?:Stat|Attribute)\s+Points?\D{0,12}(\d{1,3})/i)
      reading["unspent_attribute_points"] = match[1].to_i if match
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end
  end
end
