# frozen_string_literal: true

require "yaml"
require_relative "tesseract_letter_recognizer"

module Wos
  class FixtureGlyphLetterRecognizer
    GRID_SIZE = 20
    ACTIVE_RATIO = 0.2

    LetterGuess = Data.define(:char, :confidence, :candidates) do
      def to_h
        {
          char: char,
          confidence: confidence,
          candidates: candidates
        }
      end
    end

    def initialize(template_path: default_template_path, fallback: TesseractLetterRecognizer.new)
      @template_path = template_path
      @fallback = fallback
      @templates = load_templates
    end

    def call(tile_image)
      signature = signature_for(tile_image)
      template_candidates = @templates.map do |template|
        {
          char: template.fetch("char"),
          score: hamming_score(signature, template.fetch("signature")).round(4),
          source: "fixture_glyph"
        }
      end.sort_by { |candidate| candidate.fetch(:score) }

      return @fallback.call(tile_image) if template_candidates.empty?

      best_by_letter = template_candidates
        .group_by { |candidate| candidate.fetch(:char) }
        .map { |_char, candidates| candidates.min_by { |candidate| candidate.fetch(:score) } }
        .sort_by { |candidate| candidate.fetch(:score) }

      best = best_by_letter.fetch(0)
      second = best_by_letter.fetch(1, best)
      fallback_guess = @fallback.call(tile_image)
      candidates = best_by_letter.first(5) + fallback_guess.candidates.map { |candidate| candidate.merge(source: "tesseract_fallback") }

      LetterGuess.new(
        char: choose(best, fallback_guess),
        confidence: confidence(best.fetch(:score), second.fetch(:score), fallback_guess),
        candidates: candidates
      )
    end

    private

    def default_template_path
      return Rails.root.join("config", "wos_letter_templates.yml") if defined?(Rails)

      File.expand_path("../../../config/wos_letter_templates.yml", __dir__)
    end

    def load_templates
      return [] unless File.exist?(@template_path)

      Array(YAML.safe_load_file(@template_path))
    end

    def choose(best, fallback_guess)
      return fallback_guess.char if best.fetch(:score) > 0.34 && fallback_guess.confidence.to_f >= 0.95

      best.fetch(:char)
    end

    def confidence(best_score, second_score, fallback_guess)
      distance = 1.0 - best_score
      separation = [second_score - best_score, 0.0].max * 5.0
      fallback_bonus = fallback_guess.char == fallback_guess.candidates.first&.fetch(:char, nil) ? 0.03 : 0.0

      [[(distance * 0.75) + (separation * 0.25) + fallback_bonus, 1.0].min, 0.0].max.round(3)
    end

    def signature_for(tile_image)
      glyph = glyph_crop(grayscale(tile_image))
      data = glyph.write_to_memory.unpack("C*")
      threshold = [glyph.avg.to_f - 18.0, 135.0].min

      GRID_SIZE.times.map do |row|
        GRID_SIZE.times.map do |col|
          active_ratio_for(data, glyph.width, glyph.height, row, col, threshold) >= ACTIVE_RATIO ? "#" : "."
        end.join
      end
    end

    def grayscale(image)
      source = image.bands >= 3 ? image[0..2] : image
      source.colourspace("b-w")
    end

    def glyph_crop(gray)
      margin_x = (gray.width * 0.12).round
      margin_y = (gray.height * 0.12).round
      inner = gray.crop(
        margin_x,
        margin_y,
        [gray.width - (margin_x * 2), 1].max,
        [gray.height - (margin_y * 2), 1].max
      )
      data = inner.write_to_memory.unpack("C*")
      threshold = [inner.avg.to_f - 25.0, 120.0].min
      active_indexes = data.each_index.select { |index| data.fetch(index) <= threshold }
      return gray if active_indexes.empty?

      xs = active_indexes.map { |index| index % inner.width }
      ys = active_indexes.map { |index| index / inner.width }
      left = [xs.min - 5, 0].max
      top = [ys.min - 5, 0].max
      right = [xs.max + 5, inner.width - 1].min
      bottom = [ys.max + 5, inner.height - 1].min

      inner.crop(left, top, right - left + 1, bottom - top + 1)
    end

    def active_ratio_for(data, width, height, row, col, threshold)
      x0 = (col * width / GRID_SIZE.to_f).floor
      x1 = (((col + 1) * width / GRID_SIZE.to_f).floor) - 1
      y0 = (row * height / GRID_SIZE.to_f).floor
      y1 = (((row + 1) * height / GRID_SIZE.to_f).floor) - 1
      active = 0
      total = 0

      (y0..y1).each do |y|
        (x0..x1).each do |x|
          total += 1
          active += 1 if data.fetch(y * width + x) <= threshold
        end
      end

      active.to_f / total
    end

    def hamming_score(left, right)
      total = GRID_SIZE * GRID_SIZE
      misses = left.zip(right).sum do |actual_row, expected_row|
        actual_row.chars.zip(expected_row.chars).count { |actual, expected| actual != expected }
      end
      misses.to_f / total
    end
  end
end
