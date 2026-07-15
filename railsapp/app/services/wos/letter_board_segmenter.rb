# frozen_string_literal: true

require_relative "region"
require_relative "tile"
require_relative "fixture_glyph_letter_recognizer"

module Wos
  class LetterBoardSegmenter
    DARK_TILE_THRESHOLD = 60
    MIN_TILE_WIDTH = 90
    MIN_TILE_HEIGHT = 90
    MAX_TILE_WIDTH = 190
    MAX_TILE_HEIGHT = 190

    def initialize(letter_recognizer: FixtureGlyphLetterRecognizer.new)
      @letter_recognizer = letter_recognizer
    end

    def call(image:, region:)
      tile_regions = detected_tile_regions(image: image, region: region)

      tile_regions.each_with_index.map do |tile_region, index|
        tile_image = image.crop(tile_region.left, tile_region.top, tile_region.width, tile_region.height)
        metrics = tile_metrics(tile_image).merge(detection: "connected_component")
        letter_guess = @letter_recognizer.call(tile_image)

        Wos::Tile.new(
          index: index,
          region: tile_region,
          state: "visible",
          char: letter_guess.char,
          confidence: letter_guess.confidence,
          metrics: metrics.merge(letter_guess: letter_guess.to_h)
        )
      end
    end

    private

    def detected_tile_regions(image:, region:)
      crop = region.crop(image)
      gray = grayscale(crop)
      active = dark_mask(gray)
      boxes = connected_boxes(active: active, width: gray.width, height: gray.height)

      boxes
        .select { |box| tile_box?(box) }
        .sort_by { |box| box.fetch(:left) }
        .map do |box|
          Wos::Region.new(
            name: :letter_tile,
            left: region.left + box.fetch(:left),
            top: region.top + box.fetch(:top),
            width: box.fetch(:width),
            height: box.fetch(:height)
          )
        end
    end

    def grayscale(image)
      source = image.bands >= 3 ? image[0..2] : image
      source.colourspace("b-w")
    end

    def dark_mask(gray)
      gray.write_to_memory.unpack("C*").map { |value| value <= DARK_TILE_THRESHOLD }
    end

    def connected_boxes(active:, width:, height:)
      seen = Array.new(active.length, false)
      boxes = []

      height.times do |y|
        width.times do |x|
          index = y * width + x
          next unless active[index] && !seen[index]

          boxes << flood_box(active: active, seen: seen, width: width, height: height, start_x: x, start_y: y)
        end
      end

      boxes
    end

    def flood_box(active:, seen:, width:, height:, start_x:, start_y:)
      queue = [[start_x, start_y]]
      seen[start_y * width + start_x] = true
      min_x = max_x = start_x
      min_y = max_y = start_y
      area = 0

      until queue.empty?
        x, y = queue.pop
        area += 1
        min_x = [min_x, x].min
        max_x = [max_x, x].max
        min_y = [min_y, y].min
        max_y = [max_y, y].max

        [[1, 0], [-1, 0], [0, 1], [0, -1]].each do |dx, dy|
          nx = x + dx
          ny = y + dy
          next if nx.negative? || ny.negative? || nx >= width || ny >= height

          next_index = ny * width + nx
          next unless active[next_index] && !seen[next_index]

          seen[next_index] = true
          queue << [nx, ny]
        end
      end

      {
        left: min_x,
        top: min_y,
        width: max_x - min_x + 1,
        height: max_y - min_y + 1,
        area: area
      }
    end

    def tile_box?(box)
      box.fetch(:width).between?(MIN_TILE_WIDTH, MAX_TILE_WIDTH) &&
        box.fetch(:height).between?(MIN_TILE_HEIGHT, MAX_TILE_HEIGHT)
    end

    def tile_metrics(tile_image)
      gray = grayscale(tile_image)
      mean = gray.avg.to_f
      min = gray.min.to_f
      max = gray.max.to_f
      contrast = max - min

      {
        mean_luma: mean.round(3),
        min_luma: min.round(3),
        max_luma: max.round(3),
        contrast: contrast.round(3),
        contrast_confidence: [[contrast / 80.0, 1.0].min, 0.0].max.round(3)
      }
    end
  end
end
