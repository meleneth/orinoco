# frozen_string_literal: true

require "open3"
require "shellwords"

module Wos
  module Ocr
    class Tesseract
      DEFAULT_ALLOWLIST = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"

      Word = Data.define(:text, :confidence, :left, :top, :width, :height) do
        def right
          left + width
        end

        def bottom
          top + height
        end

        def center_x
          left + (width / 2.0)
        end

        def center_y
          top + (height / 2.0)
        end

        def to_h
          {
            text: text,
            confidence: confidence,
            left: left,
            top: top,
            width: width,
            height: height
          }
        end
      end

      class Error < StandardError; end
      class MissingBinary < Error; end

      def initialize(binary: ENV.fetch("TESSERACT_BINARY", "tesseract"), language: "eng")
        @binary = binary
        @language = language
      end

      def self.call(path, **options)
        new.call(path, **options)
      end

      def available?
        system(@binary, "--version", out: File::NULL, err: File::NULL)
      end

      def call(path, psm: 7, allowlist: DEFAULT_ALLOWLIST)
        raise MissingBinary, "tesseract binary not found: #{@binary}" unless available?

        stdout, stderr, status = Open3.capture3(*command(path, psm: psm, allowlist: allowlist))
        raise Error, stderr.strip unless status.success?

        stdout.strip
      end

      def words(path, psm: 11, allowlist: nil)
        raise MissingBinary, "tesseract binary not found: #{@binary}" unless available?

        stdout, stderr, status = Open3.capture3(*command(path, psm: psm, allowlist: allowlist, output: "tsv"))
        raise Error, stderr.strip unless status.success?

        parse_tsv(stdout)
      end

      private

      def command(path, psm:, allowlist:, output: nil)
        args = [
          @binary,
          path.to_s,
          "stdout",
          "-l",
          @language,
          "--psm",
          psm.to_s
        ]
        args.concat(["-c", "tessedit_char_whitelist=#{allowlist}"]) if allowlist
        args << output if output
        args
      end

      def parse_tsv(tsv)
        lines = tsv.to_s.lines.map(&:chomp)
        header = lines.shift.to_s.split("\t")
        indexes = header.each_with_index.to_h

        lines.filter_map do |line|
          values = line.split("\t", -1)
          next unless values[indexes.fetch("level")].to_i == 5

          text = values[indexes.fetch("text")].to_s.strip
          confidence = values[indexes.fetch("conf")].to_f
          next if text.empty? || confidence.negative?

          Word.new(
            text: text,
            confidence: confidence,
            left: values[indexes.fetch("left")].to_i,
            top: values[indexes.fetch("top")].to_i,
            width: values[indexes.fetch("width")].to_i,
            height: values[indexes.fetch("height")].to_i
          )
        end
      end
    end
  end
end