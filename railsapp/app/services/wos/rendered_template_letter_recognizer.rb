# frozen_string_literal: true

module Wos
  class RenderedTemplateLetterRecognizer
    ALPHABET = ("A".."Z").to_a.freeze
    TEMPLATE_SIZE = 64
    FONTS = [
      "Sans Bold 72",
      "Sans 72",
      "Serif Bold 72"
    ].freeze

    LetterGuess = Data.define(:char, :confidence, :candidates) do
      def to_h
        {
          char: char,
          confidence: confidence,
          candidates: candidates
        }
      end
    end

    def initialize(alphabet: ALPHABET, fonts: FONTS, template_size: TEMPLATE_SIZE)
      @alphabet = alphabet
      @fonts = fonts
      @template_size = template_size
      @templates = build_templates
    end

    def call(tile_image)
      normalized_tile = normalize(tile_image)
      candidates = @templates.map do |template|
        score = best_score(normalized_tile, template.fetch(:image))
        {
          char: template.fetch(:char),
          font: template.fetch(:font),
          score: score.round(4)
        }
      end.sort_by { |candidate| candidate.fetch(:score) }

      best = candidates.first
      confidence = score_to_confidence(best.fetch(:score), candidates.fetch(1, best).fetch(:score))

      LetterGuess.new(
        char: best.fetch(:char),
        confidence: confidence,
        candidates: collapse_candidates(candidates)
      )
    end

    private

    def build_templates
      @alphabet.flat_map do |char|
        @fonts.map do |font|
          {
            char: char,
            font: font,
            image: normalize(render_template(char, font))
          }
        end
      end
    end

    def render_template(char, font)
      text = Vips::Image.text(char, font: font, dpi: 144)
      fit_to_template_size(text)
    rescue Vips::Error
      text = Vips::Image.text(char, dpi: 144)
      fit_to_template_size(text)
    end

    def normalize(image)
      gray = grayscale(image)
      glyph = glyph_crop(gray)
      fitted = fit_to_template_size(glyph)
      min = fitted.min.to_f
      max = fitted.max.to_f
      range = max - min
      return fitted.linear(0, 0) if range <= 0.1

      fitted.linear(255.0 / range, -(min * 255.0 / range)).cast(:uchar)
    end

    def grayscale(image)
      source = image.bands >= 3 ? image[0..2] : image
      source.colourspace("b-w")
    end

    def glyph_crop(gray)
      margin_x = (gray.width * 0.12).round
      margin_y = (gray.height * 0.12).round
      inner_left = margin_x
      inner_top = margin_y
      inner_width = [gray.width - (margin_x * 2), 1].max
      inner_height = [gray.height - (margin_y * 2), 1].max
      inner = gray.crop(inner_left, inner_top, inner_width, inner_height)
      data = inner.write_to_memory.unpack("C*")
      threshold = [inner.avg.to_f - 25.0, 120.0].min
      active_indexes = data.each_index.select { |index| data.fetch(index) <= threshold }
      return gray if active_indexes.empty?

      xs = active_indexes.map { |index| index % inner.width }
      ys = active_indexes.map { |index| index / inner.width }
      left = [xs.min - 4, 0].max
      top = [ys.min - 4, 0].max
      right = [xs.max + 4, inner.width - 1].min
      bottom = [ys.max + 4, inner.height - 1].min

      inner.crop(left, top, right - left + 1, bottom - top + 1)
    end
    def fit_to_template_size(image)
      thumb = image.thumbnail_image(@template_size, height: @template_size, size: :down)
      thumb.gravity(:centre, @template_size, @template_size, extend: :white)
    end

    def best_score(tile, template)
      regular = difference_score(tile, template)
      inverted = difference_score(tile.invert, template)
      [regular, inverted].min
    end

    def difference_score(left, right)
      (left - right).abs.avg.to_f / 255.0
    end

    def score_to_confidence(best_score, next_score)
      distance_confidence = 1.0 - best_score
      separation_confidence = [next_score - best_score, 0.0].max * 4.0
      [[(distance_confidence * 0.7) + (separation_confidence * 0.3), 1.0].min, 0.0].max.round(3)
    end

    def collapse_candidates(candidates)
      candidates
        .group_by { |candidate| candidate.fetch(:char) }
        .map do |char, entries|
          best = entries.min_by { |entry| entry.fetch(:score) }
          {
            char: char,
            score: best.fetch(:score),
            font: best.fetch(:font)
          }
        end
        .sort_by { |candidate| candidate.fetch(:score) }
        .first(5)
    end
  end
end
