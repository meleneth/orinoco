# frozen_string_literal: true

module Wos
  class OfficialWordInventory
    Summary = Data.define(:length, :total, :solved, :remaining) do
      def to_h
        {
          length: length,
          total: total,
          solved: solved,
          remaining: remaining
        }
      end
    end

    def initialize(relation: nil)
      @relation = relation
    end

    def call(letters:, solved_words: [])
      available = normalized_letters(letters)
      return [] if available.empty?

      solved_counts = counts_by_length(Array(solved_words).map { |word| normalize_word(word) }.reject(&:empty?))
      totals = counts_by_length(candidate_words(available))

      totals.keys.sort.map do |length|
        total = totals.fetch(length)
        solved = [solved_counts.fetch(length, 0), total].min
        Summary.new(length: length, total: total, solved: solved, remaining: total - solved)
      end
    end

    private

    attr_reader :relation

    def candidate_words(available)
      records_for(available.length).filter_map do |word, _length|
        normalized = normalize_word(word)
        normalized if constructible?(normalized, available)
      end.uniq
    end

    def records_for(max_length)
      source = relation || default_relation
      return [] unless source

      if source.respond_to?(:where) && source.respond_to?(:pluck)
        source.where(length: 1..max_length).pluck(:word, :length)
      else
        Array(source).map do |record|
          if record.respond_to?(:word)
            [record.word, record.length]
          else
            [record.fetch(:word), record.fetch(:length)]
          end
        end
      end
    end

    def default_relation
      return nil unless defined?(::OfficialWosWord)

      ::OfficialWosWord.all
    end

    def normalized_letters(letters)
      normalize_word(letters).chars.tally
    end

    def normalize_word(word)
      word.to_s.upcase.gsub(/[^A-Z]/, "")
    end

    def constructible?(word, available)
      return false if word.empty?

      word.chars.tally.all? { |char, needed| available.fetch(char, 0) >= needed }
    end

    def counts_by_length(words)
      words.each_with_object(Hash.new(0)) do |word, counts|
        counts[word.length] += 1
      end
    end
  end
end