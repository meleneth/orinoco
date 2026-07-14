# frozen_string_literal: true

module Wos
  class ScreenshotSourceSelector
    DESKTOP_PATTERNS = [
      /display/i,
      /desktop/i,
      /screen/i,
      /monitor/i
    ].freeze

    PENALTY_PATTERNS = [
      /audio/i,
      /mic/i,
      /microphone/i
    ].freeze

    def initialize(source_names)
      @source_names = Array(source_names).map(&:to_s).map(&:strip).reject(&:empty?).uniq
    end

    def call
      @source_names.max_by { |name| score(name) }
    end

    private

    def score(name)
      score = 0
      score += 100 if DESKTOP_PATTERNS.any? { |pattern| name.match?(pattern) }
      score -= 100 if PENALTY_PATTERNS.any? { |pattern| name.match?(pattern) }
      score -= name.length * 0.001
      score
    end
  end
end