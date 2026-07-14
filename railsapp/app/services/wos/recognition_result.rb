# frozen_string_literal: true

module Wos
  class RecognitionResult
    attr_reader :source_path, :image, :regions, :ruleset, :letter_tiles, :solved_word_regions, :small_text_regions, :remaining_words, :warnings

    def initialize(source_path:, image:, regions:, ruleset:, letter_tiles:, solved_word_regions:, small_text_regions: [], remaining_words: [], warnings: [])
      @source_path = source_path.to_s
      @image = image
      @regions = regions
      @ruleset = ruleset
      @letter_tiles = letter_tiles
      @solved_word_regions = solved_word_regions
      @small_text_regions = small_text_regions
      @remaining_words = remaining_words
      @warnings = warnings
    end

    def to_h
      {
        source_path: source_path,
        image: image,
        regions: regions.transform_values(&:to_h),
        ruleset: ruleset.to_h,
        letters: letter_tiles.map(&:to_h),
        solved_words: solved_word_regions.map(&:to_h),
        small_text: small_text_regions.map(&:to_h),
        remaining_words: remaining_words.map { |summary| summary.respond_to?(:to_h) ? summary.to_h : summary },
        warnings: warnings
      }
    end
  end
end