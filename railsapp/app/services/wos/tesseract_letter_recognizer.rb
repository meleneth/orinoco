# frozen_string_literal: true

require "fileutils"
require "securerandom"
require_relative "bitmap_letter_recognizer"
require_relative "ocr/tesseract"

module Wos
  class TesseractLetterRecognizer
    ALLOWLIST = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    LetterGuess = Data.define(:char, :confidence, :candidates) do
      def to_h
        {
          char: char,
          confidence: confidence,
          candidates: candidates
        }
      end
    end

    def initialize(ocr: Ocr::Tesseract.new, fallback: BitmapLetterRecognizer.new)
      @ocr = ocr
      @fallback = fallback
    end

    def call(tile_image)
      raw = read_variant(tile_image, label: "raw", psm: 10)
      inner = read_variant(inner_enlarged(tile_image), label: "inner_enlarged", psm: 7)
      chosen = choose(raw, inner)
      return fallback_guess(tile_image, raw, inner) unless chosen

      LetterGuess.new(
        char: chosen.fetch(:char),
        confidence: confidence(chosen, raw, inner),
        candidates: candidates(raw, inner)
      )
    rescue Ocr::Tesseract::MissingBinary
      @fallback.call(tile_image)
    end

    private

    def read_variant(image, label:, psm:)
      path = File.join(temp_dir, "wos-letter-#{Process.pid}-#{SecureRandom.hex(8)}.png")
      image.write_to_file(path)
      text = @ocr.call(path, psm: psm, allowlist: ALLOWLIST)
      {
        char: normalize_text(text),
        text: text,
        source: label,
        psm: psm
      }
    rescue Ocr::Tesseract::Error
      {
        char: nil,
        text: "",
        source: label,
        psm: psm
      }
    ensure
      delete_temp_file(path) if defined?(path) && path
    end

    def delete_temp_file(path)
      File.delete(path) if File.exist?(path)
    rescue SystemCallError
      nil
    end

    def temp_dir
      dir = defined?(Rails) ? Rails.root.join("tmp", "wos-ocr").to_s : File.expand_path("../../../tmp/wos-ocr", __dir__)
      FileUtils.mkdir_p(dir)
      dir
    end

    def inner_enlarged(image)
      margin_x = (image.width * 0.12).round
      margin_y = (image.height * 0.12).round
      image
        .crop(
          margin_x,
          margin_y,
          [image.width - (margin_x * 2), 1].max,
          [image.height - (margin_y * 2), 1].max
        )
        .resize(4)
    end

    def normalize_text(text)
      letters = text.to_s.upcase.scan(/[A-Z]/)
      return nil if letters.empty?

      unique = letters.uniq
      return "O" if unique.include?("O") && (unique - ["O", "Q"]).empty?
      unique.length == 1 ? unique.first : letters.first
    end

    def choose(raw, inner)
      return inner if inner.fetch(:char) == "I" && %w[O L].include?(raw.fetch(:char))
      return inner if inner.fetch(:char) == "O" && raw.fetch(:char) == "C"

      raw.fetch(:char) ? raw : inner
    end

    def confidence(chosen, raw, inner)
      return 0.97 if raw.fetch(:char) == inner.fetch(:char) && raw.fetch(:char)
      return 0.9 if chosen.fetch(:source) == "raw" && raw.fetch(:char)
      return 0.86 if chosen.fetch(:source) == "inner_enlarged" && inner.fetch(:char)

      0.5
    end

    def candidates(raw, inner)
      [raw, inner]
        .select { |candidate| candidate.fetch(:char) }
        .map do |candidate|
          {
            char: candidate.fetch(:char),
            score: score(candidate),
            source: candidate.fetch(:source),
            text: candidate.fetch(:text),
            psm: candidate.fetch(:psm)
          }
        end
        .uniq { |candidate| [candidate.fetch(:char), candidate.fetch(:source)] }
    end

    def score(candidate)
      candidate.fetch(:source) == "raw" ? 0.0 : 0.05
    end

    def fallback_guess(tile_image, raw, inner)
      fallback = @fallback.call(tile_image)
      LetterGuess.new(
        char: fallback.char,
        confidence: fallback.confidence,
        candidates: candidates(raw, inner) + fallback.candidates.map { |candidate| candidate.merge(source: "bitmap") }
      )
    end
  end
end