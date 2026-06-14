module Overlay
  class TimerConfig
    MODES = %w[countdown].freeze

    attr_reader :timer_key, :duration_ms, :mode, :starts_on, :stops_on, :tick_rate_ms

    def initialize(timer_key:, duration_ms:, mode:, starts_on:, stops_on:, tick_rate_ms:)
      @timer_key = timer_key.to_s
      @duration_ms = duration_ms
      @mode = mode.to_s
      @starts_on = starts_on.to_s
      @stops_on = stops_on.to_s
      @tick_rate_ms = tick_rate_ms
    end

    def valid?
      validation_errors.empty?
    end

    def validate!
      return true if valid?

      raise InvalidConfigError, validation_errors.join(", ")
    end

    def validation_errors
      errors = []
      errors << "timer_key is invalid" unless timer_key.match?(identifier_regex)
      errors << "mode is invalid" unless MODES.include?(mode)
      errors << "duration_ms must be positive" unless positive_integer?(duration_ms)
      errors << "tick_rate_ms must be positive" unless positive_integer?(tick_rate_ms)
      errors << "duration_ms is too large" if positive_integer?(duration_ms) && duration_ms.to_i > 3_600_000
      errors << "tick_rate_ms is too large" if positive_integer?(tick_rate_ms) && tick_rate_ms.to_i > 60_000
      errors
    end

    def serializable_state
      validate!

      {
        "timer_key" => timer_key,
        "duration_ms" => duration_ms.to_i,
        "mode" => mode,
        "starts_on" => starts_on,
        "stops_on" => stops_on,
        "tick_rate_ms" => tick_rate_ms.to_i,
        "remaining_ms" => duration_ms.to_i,
        "remaining_label" => remaining_label
      }
    end

    def remaining_label
      seconds = duration_ms.to_i / 1000
      minutes = seconds / 60
      seconds = seconds % 60
      format("%02d:%02d", minutes, seconds)
    end

    private

    def identifier_regex
      /\A[a-zA-Z0-9_-]+\z/
    end

    def positive_integer?(value)
      Integer(value)
      value.to_i.positive?
    rescue ArgumentError, TypeError
      false
    end
  end
end
