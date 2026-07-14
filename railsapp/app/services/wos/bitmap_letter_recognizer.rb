# frozen_string_literal: true

module Wos
  class BitmapLetterRecognizer
    ROWS = 7
    COLS = 5
    ACTIVE_RATIO = 0.18

    # These seed patterns are WOS-tuned from the starter screenshots. They are intentionally
    # coarse: the recognizer should survive antialiasing and small OBS scaling changes.
    PATTERNS = {
      "A" => [".##..", ".##..", ".###.", "####.", "####.", "##.#.", "....#"],
      "E" => ["####.", "####.", "###..", "####.", "###..", "####.", "....#"],
      "H" => ["##.#.", "####.", "####.", "####.", "####.", "####.", "....#"],
      "I" => ["####.", "####.", ".##..", ".##..", ".##..", ".##..", "....#"],
      "L" => ["##...", "##...", "##...", "##...", "###..", "####.", "....#"],
      "O" => [".##..", "####.", "####.", "####.", "####.", "####.", "...##"],
      "Z" => ["####.", "####.", ".##..", ".##..", "####.", "####.", "....#"],
      "B" => ["###..", "#..#.", "#..#.", "###..", "#..#.", "#..#.", "###.."],
      "C" => [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
      "D" => ["###..", "#..#.", "#...#", "#...#", "#...#", "#..#.", "###.."],
      "F" => ["####.", "#....", "#....", "###..", "#....", "#....", "#...."],
      "G" => [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
      "J" => ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
      "K" => ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
      "M" => ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
      "N" => ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
      "P" => ["###..", "#..#.", "#..#.", "###..", "#....", "#....", "#...."],
      "Q" => [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
      "R" => ["###..", "#..#.", "#..#.", "###..", "#.#..", "#..#.", "#...#"],
      "S" => [".###.", "#...#", "#....", ".###.", "....#", "#...#", ".###."],
      "T" => ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
      "U" => ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
      "V" => ["#...#", "#...#", "#...#", "#...#", ".#.#.", ".#.#.", "..#.."],
      "W" => ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
      "X" => ["#...#", ".#.#.", "..#..", "..#..", "..#..", ".#.#.", "#...#"],
      "Y" => ["#...#", ".#.#.", "..#..", "..#..", "..#..", "..#..", "..#.."]
    }.freeze

    LetterGuess = Data.define(:char, :confidence, :candidates) do
      def to_h
        {
          char: char,
          confidence: confidence,
          candidates: candidates
        }
      end
    end

    def call(tile_image)
      signature = signature_for(tile_image)
      candidates = PATTERNS.map do |char, pattern|
        score = hamming_score(signature, pattern)
        { char: char, score: score.round(4), signature: pattern }
      end.sort_by { |candidate| candidate.fetch(:score) }

      best = candidates.first
      second = candidates.fetch(1, best)
      LetterGuess.new(
        char: best.fetch(:char),
        confidence: confidence(best.fetch(:score), second.fetch(:score)),
        candidates: candidates.first(5)
      )
    end

    private

    def signature_for(tile_image)
      glyph = glyph_crop(grayscale(tile_image))
      data = glyph.write_to_memory.unpack("C*")
      threshold = [glyph.avg.to_f - 10.0, 150.0].min

      ROWS.times.map do |row|
        COLS.times.map do |col|
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
      left = [xs.min - 4, 0].max
      top = [ys.min - 4, 0].max
      right = [xs.max + 4, inner.width - 1].min
      bottom = [ys.max + 4, inner.height - 1].min

      inner.crop(left, top, right - left + 1, bottom - top + 1)
    end

    def active_ratio_for(data, width, height, row, col, threshold)
      x0 = (col * width / COLS.to_f).floor
      x1 = (((col + 1) * width / COLS.to_f).floor) - 1
      y0 = (row * height / ROWS.to_f).floor
      y1 = (((row + 1) * height / ROWS.to_f).floor) - 1
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

    def hamming_score(signature, pattern)
      total = ROWS * COLS
      misses = signature.zip(pattern).sum do |actual_row, expected_row|
        actual_row.chars.zip(expected_row.chars).count { |actual, expected| actual != expected }
      end
      misses.to_f / total
    end

    def confidence(best_score, second_score)
      distance_confidence = 1.0 - best_score
      separation_confidence = [second_score - best_score, 0.0].max * 3.0
      [[(distance_confidence * 0.8) + (separation_confidence * 0.2), 1.0].min, 0.0].max.round(3)
    end
  end
end
