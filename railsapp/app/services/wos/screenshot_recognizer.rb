# frozen_string_literal: true

require_relative "image_loader"
require_relative "region_map"
require_relative "letter_board_segmenter"
require_relative "solved_words_segmenter"
require_relative "small_text_segmenter"
require_relative "recognition_result"
require_relative "ruleset_resolver"
require_relative "screen_remaining_words"
require_relative "debug_exporter"

module Wos
  class ScreenshotRecognizer
    def initialize(
      region_map: RegionMap.new,
      letter_board_segmenter: LetterBoardSegmenter.new,
      solved_words_segmenter: SolvedWordsSegmenter.new,
      small_text_segmenter: SmallTextSegmenter.new,
      ruleset_resolver: RulesetResolver.new,
      remaining_words_recognizer: ScreenRemainingWords.new
    )
      @region_map = region_map
      @letter_board_segmenter = letter_board_segmenter
      @solved_words_segmenter = solved_words_segmenter
      @small_text_segmenter = small_text_segmenter
      @ruleset_resolver = ruleset_resolver
      @remaining_words_recognizer = remaining_words_recognizer
    end

    def self.call(path, debug_dir: nil)
      new.call(path, debug_dir: debug_dir)
    end

    def call(path, debug_dir: nil)
      image = ImageLoader.load(path)
      regions = @region_map.for_image(width: image.width, height: image.height)
      letter_tiles = @letter_board_segmenter.call(image: image, region: regions.fetch(:letter_board))
      board_letters = letter_tiles.filter_map(&:char).join
      solved_word_regions = @solved_words_segmenter.call(image: image, region: regions.fetch(:solved_words), letters: board_letters)
      small_text_regions = @small_text_segmenter.call(
        image: image,
        regions: regions.slice(:solved_words, :status_text)
      )
      ruleset = @ruleset_resolver.call(image: image, regions: regions, small_text_regions: small_text_regions)
      remaining_words = @remaining_words_recognizer.call(
        letters: board_letters,
        solved_word_regions: solved_word_regions
      )

      result = RecognitionResult.new(
        source_path: path,
        image: {
          width: image.width,
          height: image.height,
          bands: image.bands,
          interpretation: image.interpretation.to_s
        },
        regions: regions,
        ruleset: ruleset,
        letter_tiles: letter_tiles,
        solved_word_regions: solved_word_regions,
        small_text_regions: small_text_regions,
        remaining_words: remaining_words,
        warnings: warnings_for(letter_tiles, solved_word_regions, small_text_regions)
      )

      DebugExporter.new(output_dir: debug_dir).export!(image: image, result: result) if debug_dir
      result
    end

    private

    def warnings_for(letter_tiles, solved_word_regions, small_text_regions)
      warnings = []
      visible_letters = letter_tiles.count { |tile| tile.state == "visible" }
      visible_words = solved_word_regions.count { |row| row.state == "visible_unread" }
      visible_small_text = small_text_regions.count { |row| row.state == "visible_unread" }

      warnings << "letter board segmentation found no visible tiles" if visible_letters.zero?
      warnings << "solved word region has no visible rows; this can be normal on higher difficulty" if visible_words.zero?
      warnings << "small text segmentation found no visible snippets" if visible_small_text.zero?
      warnings
    end
  end
end
