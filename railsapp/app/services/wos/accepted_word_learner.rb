# frozen_string_literal: true

module Wos
  class AcceptedWordLearner
    DEFAULT_SOURCE = "wos_screen"

    def initialize(relation: OfficialWosWord, clock: -> { Time.current })
      @relation = relation
      @clock = clock
    end

    def call(recognition:, observed_at: nil, source: DEFAULT_SOURCE)
      seen_at = normalize_time(observed_at) || clock.call
      accepted_words(recognition).each do |word|
        learn_word!(word: word, source: source, seen_at: seen_at)
      end
    end

    private

    attr_reader :relation, :clock

    def accepted_words(recognition)
      Array(recognition.to_h["solved_words"]).filter_map do |row|
        normalized = normalize_word(row["correct_word"] || row["text"])
        normalized if normalized.length >= 2
      end.uniq
    end

    def learn_word!(word:, source:, seen_at:)
      record = relation.find_or_initialize_by(word: word)
      metadata = record.metadata.is_a?(Hash) ? record.metadata : {}
      record.source = source if record.source.blank?
      record.metadata = metadata.merge(
        "first_seen_at" => metadata.fetch("first_seen_at", seen_at.iso8601(6)),
        "last_seen_at" => seen_at.iso8601(6),
        "seen_count" => metadata.fetch("seen_count", 0).to_i + 1
      )
      record.save!
      record
    end

    def normalize_word(word)
      word.to_s.upcase.gsub(/[^A-Z]/, "")
    end

    def normalize_time(value)
      return value if value.respond_to?(:iso8601)
      return nil if value.nil? || value.to_s.empty?

      Time.zone.parse(value.to_s)
    end
  end
end