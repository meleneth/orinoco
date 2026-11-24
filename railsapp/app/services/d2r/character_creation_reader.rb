# frozen_string_literal: true

require "open3"
require "tempfile"
require "vips"

module D2r
  class CharacterCreationReader
    CLASSES = %w[Amazon Assassin Barbarian Druid Necromancer Paladin Sorceress].freeze
    REGIONS = {
      character_class: [ 0.40, 0.13, 0.20, 0.055 ],
      name: [ 0.392, 0.805, 0.215, 0.055 ],
      game_version: [ 0.74, 0.835, 0.20, 0.055 ]
    }.freeze

    def call(path)
      image = Vips::Image.new_from_file(path.to_s, access: :random)
      {
        "character_class" => parse_class(ocr(crop(image, REGIONS.fetch(:character_class)), psm: 7)),
        "name" => parse_name(ocr(crop(image, REGIONS.fetch(:name)), psm: 7)),
        "game_version" => parse_game_version(ocr(crop(image, REGIONS.fetch(:game_version)), psm: 7))
      }.compact
    rescue Vips::Error
      {}
    end

    def self.normalize(value)
      value.to_s.downcase.tr("@®0", "ooo").gsub(/[^a-z0-9]+/, " ").strip.gsub(/\s+/, " ")
    end

    private

    def parse_class(text)
      normalized = self.class.normalize(text)
      tokens = normalized.split
      CLASSES.find do |name|
        target = name.downcase
        tokens.any? { |token| edit_distance(token, target) <= 2 }
      end
    end

    def parse_name(text)
      text.to_s.scan(/[A-Za-z][A-Za-z_-]{1,14}/).find do |token|
        !%w[character name create back].include?(token.downcase)
      end
    end

    def parse_game_version(text)
      normalized = self.class.normalize(text)
      value = normalized.sub(/.*game version\s*/, "")
      value.empty? ? nil : value.split.map(&:capitalize).join(" ")
    end

    def crop(image, rect)
      left = (image.width * rect.fetch(0)).round.clamp(0, image.width - 1)
      top = (image.height * rect.fetch(1)).round.clamp(0, image.height - 1)
      width = (image.width * rect.fetch(2)).round.clamp(1, image.width - left)
      height = (image.height * rect.fetch(3)).round.clamp(1, image.height - top)
      image.crop(left, top, width, height)
    end

    def ocr(image, psm:)
      Tempfile.create([ "d2r-character-creation-", ".png" ]) do |file|
        image.colourspace("b-w").resize(2.0).sharpen.write_to_file(file.path)
        output, status = Open3.capture2(
          "tesseract", file.path, "stdout", "-l", "eng", "--psm", psm.to_s,
          err: File::NULL
        )
        status.success? ? output : ""
      end
    rescue Errno::ENOENT
      ""
    end

    def edit_distance(left, right)
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
