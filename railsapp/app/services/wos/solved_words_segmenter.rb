# frozen_string_literal: true

require "fileutils"
require "securerandom"
require_relative "region"
require_relative "ocr/tesseract"

module Wos
  class SolvedWordsSegmenter
    BRIGHT_THRESHOLD = 200
    DARK_THRESHOLD = 65
    MIN_COMPONENT_AREA = 18
    MAX_COMPONENT_AREA = 2_000
    MIN_COMPONENT_WIDTH = 3
    MIN_COMPONENT_HEIGHT = 5
    LINE_Y_TOLERANCE = 10
    LINE_GAP_TOLERANCE = 18
    MIN_SLOT_COMPONENTS = 6
    MAX_SLOT_HEIGHT = 28
    ANSWER_HEADER_PADDING = 80
    ANSWER_MAX_OFFSET = 90
    MIN_ACCEPTED_CONFIDENCE = 70.0
    WORD_ALLOWLIST = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-: "
    UI_WORDS = %w[FOUND STREAM WORDS WORD ON THE FIRST ANAGRAM GOAL CODE JOIN SCAN GAME].freeze

    SolvedWordRegion = Data.define(:index, :region, :state, :text, :player, :confidence, :metrics, :word_length, :filled_count, :correct_word, :raw_text) do
      def to_h
        {
          index: index,
          region: region.to_h,
          state: state,
          text: text,
          player: player,
          confidence: confidence,
          word_length: word_length,
          filled_count: filled_count,
          correct_word: correct_word,
          raw_text: raw_text,
          metrics: metrics
        }
      end
    end

    def initialize(ocr: Ocr::Tesseract.new)
      @ocr = ocr
    end

    def call(image:, region:, letters: "")
      entries = line_entries(image: image, region: region)
      blank_regions = entries
        .select { |entry| word_slot?(entry) }
        .sort_by { |entry| [entry.fetch(:region).top, entry.fetch(:region).left] }
        .map { |entry| build_blank_region(entry: entry) }

      accepted_regions = accepted_word_regions(image: image, region: region, letters: letters)

      (accepted_regions + blank_regions)
        .sort_by { |row| [row.region.top, row.region.left, row.state == "solved" ? 0 : 1] }
        .each_with_index
        .map { |row, index| row.with(index: index) }
    end

    private

    attr_reader :ocr

    def build_blank_region(entry:)
      components = entry.fetch(:components)
      word_length = estimate_word_length(components)
      metrics = entry.fetch(:metrics).merge(
        component_count: components.length,
        component_boxes: components.map { |component| component.except(:pixels) },
        detection: "word_slot_components"
      )

      SolvedWordRegion.new(
        index: 0,
        region: entry.fetch(:region),
        state: "blank",
        text: nil,
        player: nil,
        confidence: confidence_for(components),
        metrics: metrics,
        word_length: word_length,
        filled_count: 0,
        correct_word: nil,
        raw_text: ""
      )
    end

    def accepted_word_regions(image:, region:, letters:)
      available = normalized_letters(letters)
      return [] if available.empty?

      ocr_region = answer_ocr_region(image: image, region: region)
      words = ocr_words(image: image, region: ocr_region)
      candidates = words.select { |word| accepted_word_candidate?(word, available: available, letters: letters, region: region) }

      candidates.uniq { |word| [clean_word(word.text), word.left / 10, word.top / 10] }.map do |word|
        correct_word = clean_word(word.text)
        player = player_for(word: word, words: words, correct_word: correct_word)
        row_region = Wos::Region.new(
          name: :solved_word_row,
          left: ocr_region.left + word.left,
          top: ocr_region.top + word.top,
          width: word.width,
          height: word.height
        )

        SolvedWordRegion.new(
          index: 0,
          region: row_region,
          state: "solved",
          text: correct_word,
          player: player,
          confidence: (word.confidence / 100.0).round(3),
          metrics: {
            detection: "tesseract_word_box",
            ocr_word: word.to_h,
            player_source: player
          },
          word_length: correct_word.length,
          filled_count: correct_word.length,
          correct_word: correct_word,
          raw_text: word.text
        )
      end
    end

    def answer_ocr_region(image:, region:)
      top = [region.top - ANSWER_HEADER_PADDING, 0].max
      bottom = [region.top + ANSWER_MAX_OFFSET + 50, image.height].min
      Wos::Region.new(
        name: :solved_answer_ocr,
        left: region.left,
        top: top,
        width: region.width,
        height: [bottom - top, 1].max
      )
    end

    def ocr_words(image:, region:)
      path = File.join(temp_dir, "wos-solved-#{Process.pid}-#{SecureRandom.hex(8)}.png")
      region.crop(image).write_to_file(path)
      ocr.words(path, psm: 11, allowlist: WORD_ALLOWLIST)
    rescue Ocr::Tesseract::Error
      []
    ensure
      delete_temp_file(path) if defined?(path) && path
    end

    def accepted_word_candidate?(word, available:, letters:, region:)
      clean = clean_word(word.text)
      return false if clean.length < 3
      return false if clean == clean_word(letters)
      return false if UI_WORDS.include?(clean)
      return false if word.confidence < MIN_ACCEPTED_CONFIDENCE
      return false if word.top > ANSWER_HEADER_PADDING + ANSWER_MAX_OFFSET

      constructible?(clean, available)
    end

    def player_for(word:, words:, correct_word:)
      candidates = words.select do |candidate|
        clean = clean_word(candidate.text)
        !clean.empty? &&
          clean != correct_word &&
          !UI_WORDS.include?(clean) &&
          candidate.top < word.top &&
          (candidate.center_x - word.center_x).abs <= 160 &&
          candidate.confidence >= 50
      end

      candidates.min_by { |candidate| [word.top - candidate.top, (candidate.center_x - word.center_x).abs] }&.text&.gsub(/[^A-Za-z0-9_-]/, "")
    end

    def clean_word(text)
      text.to_s.upcase.gsub(/[^A-Z]/, "")
    end

    def normalized_letters(letters)
      clean_word(letters).chars.tally
    end

    def constructible?(word, available)
      word.chars.tally.all? { |char, needed| available.fetch(char, 0) >= needed }
    end

    def line_entries(image:, region:)
      crop = region.crop(image)
      gray = grayscale(crop)
      boxes = component_boxes(gray)

      group_into_lines(boxes).map do |line|
        box = merged_box(line)
        line_region = Wos::Region.new(
          name: :solved_word_row,
          left: region.left + box.fetch(:left),
          top: region.top + box.fetch(:top),
          width: box.fetch(:width),
          height: box.fetch(:height)
        )

        {
          region: line_region,
          components: line,
          metrics: line_metrics(line)
        }
      end
    end

    def grayscale(image)
      source = image.bands >= 3 ? image[0..2] : image
      source.colourspace("b-w")
    end

    def component_boxes(gray)
      data = gray.write_to_memory.unpack("C*")
      active = data.map { |value| value >= BRIGHT_THRESHOLD || value <= DARK_THRESHOLD }
      connected_boxes(active: active, width: gray.width, height: gray.height)
        .select { |box| text_component?(box) }
        .sort_by { |box| [box.fetch(:top), box.fetch(:left)] }
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
      pixels = 0

      until queue.empty?
        x, y = queue.pop
        pixels += 1
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
        pixels: pixels
      }
    end

    def text_component?(box)
      box.fetch(:pixels).between?(MIN_COMPONENT_AREA, MAX_COMPONENT_AREA) &&
        box.fetch(:width) >= MIN_COMPONENT_WIDTH &&
        box.fetch(:height) >= MIN_COMPONENT_HEIGHT
    end

    def group_into_lines(boxes)
      rows = []

      boxes.each do |box|
        row = rows.find { |candidate| vertical_neighbors?(candidate, box) }
        if row
          row << box
        else
          rows << [box]
        end
      end

      rows.flat_map { |row| split_wide_gaps(row.sort_by { |box| box.fetch(:left) }) }
        .select { |line| line.length >= 2 }
    end

    def vertical_neighbors?(line, box)
      line_box = merged_box(line)
      center_delta = (center_y(line_box) - center_y(box)).abs
      center_delta <= LINE_Y_TOLERANCE || overlaps_vertically?(line_box, box)
    end

    def split_wide_gaps(row)
      lines = [[]]
      row.each do |box|
        current = lines.last
        if current.empty? || box.fetch(:left) - right_edge(current.last) <= LINE_GAP_TOLERANCE
          current << box
        else
          lines << [box]
        end
      end
      lines
    end

    def word_slot?(entry)
      line_region = entry.fetch(:region)
      components = entry.fetch(:components)
      components.length >= MIN_SLOT_COMPONENTS && line_region.height <= MAX_SLOT_HEIGHT
    end

    def estimate_word_length(components)
      (components.length / 2.0).ceil
    end

    def line_metrics(components)
      box = merged_box(components)
      {
        width: box.fetch(:width),
        height: box.fetch(:height),
        confidence: confidence_for(components)
      }
    end

    def confidence_for(components)
      [[components.length / 8.0, 1.0].min, 0.0].max.round(3)
    end

    def merged_box(boxes)
      left = boxes.map { |box| box.fetch(:left) }.min
      top = boxes.map { |box| box.fetch(:top) }.min
      right = boxes.map { |box| right_edge(box) }.max
      bottom = boxes.map { |box| bottom_edge(box) }.max

      {
        left: left,
        top: top,
        width: right - left + 1,
        height: bottom - top + 1
      }
    end

    def center_y(box)
      box.fetch(:top) + (box.fetch(:height) / 2.0)
    end

    def right_edge(box)
      box.fetch(:left) + box.fetch(:width) - 1
    end

    def bottom_edge(box)
      box.fetch(:top) + box.fetch(:height) - 1
    end

    def overlaps_vertically?(left, right)
      [left.fetch(:top), right.fetch(:top)].max <= [bottom_edge(left), bottom_edge(right)].min
    end

    def temp_dir
      dir = defined?(Rails) ? Rails.root.join("tmp", "wos-ocr").to_s : File.expand_path("../../../tmp/wos-ocr", __dir__)
      FileUtils.mkdir_p(dir)
      dir
    end

    def delete_temp_file(path)
      File.delete(path) if File.exist?(path)
    rescue SystemCallError
      nil
    end
  end
end