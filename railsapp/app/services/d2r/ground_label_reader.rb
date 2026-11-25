# frozen_string_literal: true

require "csv"
require "open3"
require "set"
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
    UNIQUE_LABELS = File.foreach(File.expand_path("../../../config/d2r_unique_ground_labels.txt", __dir__))
      .map(&:strip).reject { |line| line.empty? || line.start_with?("#") }.to_set.freeze
    # Ground labels are read only from the playfield. Chat/system messages
    # occupy the lower-left, can share unique-item gold, and must never be
    # considered loot even when OCR drops the chat prefix.
    CHAT_LEFT_FRACTION = 0.65
    CHAT_TOP_FRACTION = 0.52

    def call(path)
      image = Vips::Image.new_from_file(path.to_s, access: :random)
      return [] if image.bands < 3

      top = (image.height * 0.20).round
      height = (image.height * 0.72).round.clamp(1, image.height - top)
      bottom = top + height
      chat_right = (image.width * CHAT_LEFT_FRACTION).ceil
      chat_top = (image.height * CHAT_TOP_FRACTION).floor
      tsv, status = Open3.capture2(
        "tesseract", path.to_s, "stdout", "--psm", "11", "-l", "eng", "tsv",
        err: File::NULL
      )
      return [] unless status.success?

      lines = CSV.parse(tsv, headers: true, col_sep: "\t").filter_map do |row|
        word_top = row["top"].to_i
        next unless row["level"] == "5" && row["conf"].to_f >= MIN_WORD_CONFIDENCE
        next unless word_top.between?(top, bottom - 1)
        # Reject any word whose box intersects the untrusted chat region.
        # Gate before grouping and rune matching, not after OCR interpretation.
        word_left = row["left"].to_i
        word_right = word_left + row["width"].to_i
        word_bottom = word_top + row["height"].to_i
        next if word_left < chat_right && word_bottom > chat_top
        word = row["text"].to_s.strip
        next if word.empty?

        {
          group: %w[page_num block_num par_num line_num].map { |key| row[key] },
          text: word,
          left: word_left,
          top: word_top,
          width: row["width"].to_i,
          height: row["height"].to_i
        }
      end.group_by { |word| word.fetch(:group) }

      lines.flat_map do |_, words|
        label = words.map { |word| word.fetch(:text) }.join(" ").strip
        next [] if label.empty?
        # Gold chat/system text shares the unique-item palette. Reject it
        # before rune parsing as well, otherwise a chat line mentioning loot
        # could be persisted as a ground drop.
        next [] if chat_or_system_label?(label)

        rune_names = label.scan(RUNE_PATTERN).flatten.filter_map do |match|
          rune = LootTracker::RUNES.find { |name| name.casecmp?(match) }
          { "kind" => "rune", "name" => "#{rune} Rune", "confidence" => "candidate" } if rune
        end
        next rune_names unless rune_names.empty?

        # Player names can appear gold too. Require a complete known unique
        # name or base label before treating the color as item evidence.
        next [] unless UNIQUE_LABELS.include?(label.downcase.tr("’", "'"))

        required_gold_words = words.length == 1 ? 1 : 2
        if words.count { |word| gold_word?(image, word) } >= required_gold_words
          [ { "kind" => "unique", "name" => label, "confidence" => "candidate" } ]
        else
          []
        end
      end.uniq
    rescue Vips::Error, Errno::ENOENT, CSV::MalformedCSVError => e
      Rails.logger.warn("[d2r-ground-label] extraction failed: #{e.class}: #{e.message}") if defined?(Rails)
      []
    end

    private

    def chat_or_system_label?(label)
      label.match?(/\A\s*\[?Game\]?(?:\s|$)/i) ||
        label.match?(/\bsays\b/i) ||
        label.match?(/\A\s*:/) ||
        label.match?(/\b(?:I\s+)?(?:am\s+)?overburdened\b/i) ||
        label.match?(/\b(?:can't\s+)?carry\s+anymore\b/i) ||
        label.match?(/\b(?:need\s+)?(?:a|the)\s+key\b/i) ||
        label.match?(/\bnot\s+in\s+town\b/i) ||
        label.match?(/\b(?:sisters\s+succumbed|call\s+of\s+anguish)\b/i)
    end

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
