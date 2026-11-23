# frozen_string_literal: true

require "open3"
require "tempfile"
require "vips"

module D2r
  # A deliberately conservative candidate extractor. OCR is evidence, not a
  # confirmed pickup: the tracker emits "sighted" only after repeated frames.
  # The gameplay capture is scanned at its native resolution, preserving
  # 1920x1200 glyph detail.
  class GroundLabelReader
    RUNE_PATTERN = /\b(#{Regexp.union(LootTracker::RUNES).source})\s+Rune\b/i
    # D2R unique item text is gold. Arbitrary yellow text is not proof of a
    # unique, so emit candidate names only after spatial/color filtering.
    MIN_CHARS = 3

    def call(path)
      image = Vips::Image.new_from_file(path.to_s)
      return [] unless image.bands >= 3

      # Item labels normally occupy the middle/lower gameplay viewport.
      top = (image.height * 0.20).round
      height = (image.height * 0.72).round.clamp(1, image.height - top)
      crop = image.crop(0, top, image.width, height)
      Tempfile.create(["d2r-ground-label-", ".png"]) do |file|
        crop.write_to_file(file.path)
        text, status = Open3.capture2("tesseract", file.path, "stdout", "--psm", "11", "-l", "eng",
                                     err: File::NULL)
        return [] unless status.success?

        lines = text.lines.map(&:strip).reject(&:empty?)
        lines.flat_map do |line|
          runes = line.scan(RUNE_PATTERN).flatten.map do |match|
            name = LootTracker::RUNES.find { |rune| rune.casecmp?(match) }
            { "kind" => "rune", "name" => "#{name} Rune" } if name
          end.compact
          # Unique names require a separate color-aware recognizer and labeled
          # captures. Never infer uniqueness solely from ordinary OCR text.
          runes
        end.uniq
      end
    rescue Vips::Error, Errno::ENOENT => e
      Rails.logger.warn("[d2r-ground-label] extraction failed: #{e.class}: #{e.message}") if defined?(Rails)
      []
    end
  end
end
