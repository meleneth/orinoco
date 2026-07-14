# frozen_string_literal: true

module Wos
  class ScreenRemainingWords
    Summary = Data.define(:length, :total, :solved, :remaining, :source) do
      def to_h
        {
          length: length,
          total: total,
          solved: solved,
          remaining: remaining,
          source: source
        }
      end
    end

    GROUP_TOLERANCE = 24

    def call(letters:, solved_word_regions: [])
      blanks = Array(solved_word_regions).select { |row| row.state == "blank" && row.word_length.to_i.positive? }
      return [] if blanks.empty?

      groups = vertical_groups(blanks)
      board_length = letters.to_s.length

      summaries = if board_length == 6 && groups.length >= 2
        six_letter_bank_summaries(groups)
      else
        fallback_summaries(blanks)
      end

      summaries.select { |summary| summary.remaining.positive? }
    end

    private

    def six_letter_bank_summaries(groups)
      first_bank = groups.fetch(0)
      second_bank = groups.fetch(1)
      four_letter_count = first_bank.map { |row| row.word_length.to_i }.max.to_i
      five_letter_cells = second_bank.sum { |row| row.word_length.to_i }
      five_letter_count = (five_letter_cells / 5.0).round

      [
        Summary.new(length: 4, total: four_letter_count, solved: 0, remaining: four_letter_count, source: "screen_blank_bank"),
        Summary.new(length: 5, total: five_letter_count, solved: 0, remaining: five_letter_count, source: "screen_blank_bank")
      ]
    end

    def fallback_summaries(blanks)
      blanks.group_by { |row| row.word_length.to_i }.sort.map do |length, rows|
        Summary.new(length: length, total: rows.length, solved: 0, remaining: rows.length, source: "screen_blank_rows")
      end
    end

    def vertical_groups(rows)
      rows.sort_by { |row| [row.region.top, row.region.left] }.each_with_object([]) do |row, groups|
        group = groups.find { |candidate| (candidate.first.region.top - row.region.top).abs <= GROUP_TOLERANCE }
        if group
          group << row
        else
          groups << [row]
        end
      end.sort_by { |group| group.map { |row| row.region.top }.min }
    end
  end
end