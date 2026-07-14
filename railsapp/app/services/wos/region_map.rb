# frozen_string_literal: true

require_relative "region"

module Wos
  class RegionMap
    CANONICAL_WIDTH = 1920
    CANONICAL_HEIGHT = 1080

    DEFAULT_REGIONS = {
      game: Region.new(name: :game, left: 0, top: 0, width: 1920, height: 1080),
      letter_board: Region.new(name: :letter_board, left: 390, top: 250, width: 1140, height: 190),
      solved_words: Region.new(name: :solved_words, left: 250, top: 100, width: 1420, height: 420),
      status_text: Region.new(name: :status_text, left: 1180, top: 790, width: 620, height: 230)
    }.freeze

    def initialize(regions: DEFAULT_REGIONS, canonical_width: CANONICAL_WIDTH, canonical_height: CANONICAL_HEIGHT)
      @regions = regions
      @canonical_width = canonical_width
      @canonical_height = canonical_height
    end

    def for_image(width:, height:)
      @regions.transform_values do |region|
        region.scale_from(
          source_width: @canonical_width,
          source_height: @canonical_height,
          target_width: width,
          target_height: height
        )
      end
    end
  end
end
