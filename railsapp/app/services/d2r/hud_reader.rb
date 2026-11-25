# frozen_string_literal: true

require "vips"

module D2r
  # Reads D2R's top-right automap information without relying on OCR. The
  # Exocet-style HUD font is consistently missed by stock Tesseract, while its
  # colored, right-aligned glyph rows are stable enough for normalized bitmap
  # matching against confirmed captures.
  class HudReader
    ROI = { x: 0.7917, y: 0.0, width: 0.2083, height: 0.15 }.freeze
    NORMALIZED_WIDTH = 400
    NORMALIZED_HEIGHT = 180
    FEATURE_WIDTH = 400
    FEATURE_HEIGHT = 40
    MAX_DISTANCE = 0.42

    REFERENCES = [
      {
        file: "hud_rogue_encampment.png",
        gold: [ "Rogue Encampment", "Difficulty: Hell" ],
        purple: [ "__modifier__", "Canyon of the Magi", "Tal Rasha's Tomb", "Tal Rasha's Chamber" ]
      },
      {
        file: "hud_harrogath.png",
        gold: [ "Harrogath", "Difficulty: Hell" ],
        purple: [ "__modifier__", "Barracks", "Jail" ]
      },
      {
        file: "hud_catacombs_level_2.png",
        gold: [ "Catacombs Level 2", "Difficulty: Hell" ],
        purple: [ "__modifier__", "Dry Hills", "Halls of the Dead" ]
      },
      {
        file: "hud_catacombs_level_3.png",
        gold: [ "Catacombs Level 3", "Difficulty: Hell" ],
        purple: [ "__modifier__", "Rocky Waste", "Stony Tomb" ]
      },
      {
        file: "hud_tamoe_highland_normal.png",
        gold: [],
        purple: [ "Tamoe Highland", "Pit", "Monastery Gate", "Outer Cloister" ]
      }
    ].freeze

    def initialize(reference_root: Rails.root.join("spec/fixtures/files/d2r/hud"))
      @reference_root = Pathname(reference_root)
    end

    def call(path)
      rows = rows_for(normalized_hud(Vips::Image.new_from_file(path.to_s, access: :sequential)))
      gold = rows.fetch(:gold).filter_map { |feature| match(feature, :gold) }
      # Match every row because the optional modifier may be absent.
      purple_rows = rows.fetch(:purple)
      purple = purple_rows.filter_map { |feature| match(feature, :purple) }
      purple.delete("__modifier__")

      {
        "area" => gold.find { |label| !label.start_with?("Difficulty:") },
        "difficulty" => gold.filter_map { |label| label[/\ADifficulty:\s*(.+)\z/, 1] }.first,
        "terror_zones" => (purple.uniq if purple_rows.empty? || !purple.empty?)
      }.compact
    rescue Vips::Error
      {}
    end

    private

    def references
      @references ||= REFERENCES.flat_map do |reference|
        image = Vips::Image.new_from_file(@reference_root.join(reference.fetch(:file)).to_s, access: :sequential)
        rows = rows_for(image.resize(NORMALIZED_WIDTH.fdiv(image.width), vscale: NORMALIZED_HEIGHT.fdiv(image.height)))
        %i[gold purple].flat_map do |color|
          rows.fetch(color).zip(reference.fetch(color)).filter_map do |feature, label|
            { color:, label:, feature: } if label
          end
        end
      end
    end

    def match(feature, color)
      candidate, distance = references.filter { |reference| reference.fetch(:color) == color }
        .map { |reference| [ reference, feature_distance(feature, reference.fetch(:feature)) ] }
        .min_by(&:last)
      candidate.fetch(:label) if distance && distance <= MAX_DISTANCE
    end

    def normalized_hud(image)
      left = (image.width * ROI.fetch(:x)).round.clamp(0, image.width - 1)
      top = (image.height * ROI.fetch(:y)).round.clamp(0, image.height - 1)
      width = (image.width * ROI.fetch(:width)).round.clamp(1, image.width - left)
      height = (image.height * ROI.fetch(:height)).round.clamp(1, image.height - top)
      image.crop(left, top, width, height).resize(NORMALIZED_WIDTH.fdiv(width), vscale: NORMALIZED_HEIGHT.fdiv(height))
    end

    def rows_for(image)
      pixels = image[0..2].cast("uchar").write_to_memory.unpack("C*")
      masks = { gold: Array.new(image.width * image.height, false), purple: Array.new(image.width * image.height, false) }
      image.height.times do |y|
        image.width.times do |x|
          offset = ((y * image.width) + x) * 3
          red, green, blue = pixels.slice(offset, 3)
          index = (y * image.width) + x
          masks[:gold][index] = gold_pixel?(red, green, blue)
          masks[:purple][index] = purple_pixel?(red, green, blue)
        end
      end
      {
        gold: line_features(masks.fetch(:gold), image.width, image.height, min_span: 25),
        purple: line_features(masks.fetch(:purple), image.width, image.height, min_span: 20)
      }
    end

    def gold_pixel?(red, green, blue)
      red >= 75 && green >= 60 && red >= (blue * 1.3) && green >= (blue * 1.15)
    end

    def purple_pixel?(red, green, blue)
      red >= 70 && blue >= 75 && red >= (green * 1.18) && blue >= (green * 1.2)
    end

    def line_features(mask, width, height, min_span:)
      active_rows = height.times.select { |y| width.times.count { |x| mask[(y * width) + x] } >= 3 }
      groups = active_rows.chunk_while { |left, right| right - left <= 2 }.to_a
      groups.filter_map do |rows|
        points = rows.flat_map do |y|
          width.times.filter_map { |x| [ x, y ] if mask[(y * width) + x] }
        end
        next if points.empty?

        xs = points.map(&:first)
        next if xs.max < width * 0.82 || (xs.max - xs.min) < min_span

        feature_for(points, rows.min, rows.max)
      end
    end

    def feature_for(points, top, bottom)
      feature = Array.new(FEATURE_WIDTH * FEATURE_HEIGHT, false)
      source_height = [ bottom - top + 1, 1 ].max
      points.each do |x, y|
        # HUD labels are right-aligned. Keeping their absolute horizontal span
        # makes phrases of different lengths distinguishable; only normalize
        # the line height to absorb capture scaling.
        target_x = (x * FEATURE_WIDTH / NORMALIZED_WIDTH).clamp(0, FEATURE_WIDTH - 1)
        target_y = ((y - top) * FEATURE_HEIGHT / source_height).clamp(0, FEATURE_HEIGHT - 1)
        feature[(target_y * FEATURE_WIDTH) + target_x] = true
      end
      feature
    end

    def feature_distance(left, right)
      (directed_miss(left, right) + directed_miss(right, left)) / 2.0
    end

    def directed_miss(source, target)
      points = source.each_index.select { |index| source[index] }
      return 1.0 if points.empty?

      misses = points.count do |index|
        x = index % FEATURE_WIDTH
        y = index / FEATURE_WIDTH
        (-2..2).none? do |dy|
          next false unless (0...FEATURE_HEIGHT).cover?(y + dy)

          (-2..2).any? do |dx|
            (0...FEATURE_WIDTH).cover?(x + dx) && target[((y + dy) * FEATURE_WIDTH) + x + dx]
          end
        end
      end
      misses.fdiv(points.length)
    end
  end
end
