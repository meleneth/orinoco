# frozen_string_literal: true

require "csv"
require "open3"
require "tempfile"
require "vips"
require_relative "loot_tracker"

module D2r
  # Reads *visible ground labels*, not inventory ownership or guaranteed drops.
  # OCR and label color are imperfect; consumers must retain the observation's
  # evidence/confidence and never treat a sighting as a pickup.
  class GroundLabelReader
    RUNE_PATTERN = /\b(#{Regexp.union(LootTracker::RUNES).source})\s+Rune\b/i
    MIN_WORD_CONFIDENCE = 40.0
    MIN_GOLD_PIXELS = 5

    def call(path)
      # OCR writes the full crop first, then color verification revisits word
      # regions within it. Random access is required for that second pass.
      image = Vips::Image.new_from_file(path.to_s, access: :random)
      return [] if image.bands < 3

      top = (image.height * 0.20).round
      height = (image.height * 0.72).round.clamp(1, image.height - top)
      crop = image.crop(0, top, image.width, height)
      Tempfile.create([ "d2r-ground-label-", ".png" ]) do |file|
        crop.write_to_file(file.path)
        tsv, status = Open3.capture2(
          "tesseract", file.path, "stdout", "--psm", "11", "-l", "eng", "tsv",
          err: File::NULL
        )
        return [] unless status.success?

        lines = CSV.parse(tsv, headers: true, col_sep: "\t").filter_map do |row|
          next unless row["level"] == "5" && row["conf"].to_f >= MIN_WORD_CONFIDENCE
          word = row["text"].to_s.strip
          next if word.empty?

          {
            group: %w[page_num block_num par_num line_num].map { |key| row[key] },
            text: word,
            left: row["left"].to_i,
            top: row["top"].to_i,
            width: row["width"].to_i,
            height: row["height"].to_i
          }
        end.group_by { |word| word.fetch(:group) }

        lines.flat_map do |_, words|
          label = words.map { |word| word.fetch(:text) }.join(" ").strip
          next [] if label.empty?

          rune_names = label.scan(RUNE_PATTERN).flatten.filter_map do |match|
            rune = LootTracker::RUNES.find { |name| name.casecmp?(match) }
            { "kind" => "rune", "name" => "#{rune} Rune", "confidence" => "candidate" } if rune
          end
          next rune_names unless rune_names.empty?

          # Unique-item labels use gold foreground in D2R. Exclude HUD-style
          # phrases and single-word speculative detections. This is a candidate
          # requiring multiple matching screenshot confirmations downstream.
          next [] if label.length < (words.length == 1 ? 8 : 5)
          next [] if label.match?(/\b(?:Difficulty|Level|Experience|Life|Mana|Gold|Rune)\b/i)

          required_gold_words = words.length == 1 ? 1 : 2
          if words.count { |word| gold_word?(crop, word) } >= required_gold_words
            [ { "kind" => "unique", "name" => label, "confidence" => "candidate" } ]
          else
            []
          end
        end.uniq
      end
    rescue Vips::Error, Errno::ENOENT, CSV::MalformedCSVError => e
      Rails.logger.warn("[d2r-ground-label] extraction failed: #{e.class}: #{e.message}") if defined?(Rails)
      []
    end

    private

    def gold_word?(image, word)
      x0 = word.fetch(:left).clamp(0, image.width - 1)
      y0 = word.fetch(:top).clamp(0, image.height - 1)
      width = word.fetch(:width).clamp(1, image.width - x0)
      height = word.fetch(:height).clamp(1, image.height - y0)
      region = image.crop(x0, y0, width, height)
      pixels = region[0..2].cast("uchar").write_to_memory.unpack("C*")
      golden = 0
      pixels.each_slice(3) do |red, green, blue|
        next unless red >= 110 && green >= 85 && blue >= 25
        next unless red > (green * 1.07) && green > (blue * 1.28)
        next unless red < (green * 1.8)
        golden += 1
      end
      golden >= MIN_GOLD_PIXELS
    end
  end
end
