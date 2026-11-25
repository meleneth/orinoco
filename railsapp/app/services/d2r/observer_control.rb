# frozen_string_literal: true

require "json"
require "time"
require_relative "scan_presence"
require_relative "capture_gate"

module D2r
  # Redis-backed control and diagnostics shared by the observer workers and web UI.
  # A forced scan does not bypass the in-flight request gate or OBS connectivity.
  class ObserverControl
    MODES = %w[auto force_on force_off].freeze
    PREFIX = "orinoco:d2r:observer:control"
    STATUS_TTL_SECONDS = 3600

    def initialize(redis:, clock: -> { Time.now.utc })
      @redis = redis
      @clock = clock
    end

    def mode
      value = @redis.get("#{PREFIX}:mode")
      MODES.include?(value) ? value : "auto"
    end

    def mode=(value)
      raise ArgumentError, "invalid D2R scan mode" unless MODES.include?(value)

      @redis.set("#{PREFIX}:mode", value)
    end

    def record_capture(reason:, source:, error: nil)
      record("capture", "reason" => reason.to_s, "source" => source.to_s, "error" => error&.to_s)
    end

    def record_processing(reason:, source:, screen: nil, error: nil)
      record("processing", "reason" => reason.to_s, "source" => source.to_s,
        "screen" => screen&.to_s, "error" => error&.to_s)
    end

    def snapshot(source:)
      presence_key = "#{D2r::ScanPresence::KEY_PREFIX}#{source}"
      {
        mode: mode,
        capture: read("#{PREFIX}:capture"),
        processing: read("#{PREFIX}:processing"),
        presence: read(presence_key),
        pending: read(D2r::CaptureGate::KEY)
      }
    end

    private

    def record(kind, values)
      payload = values.merge("at" => @clock.call.iso8601(6))
      @redis.set("#{PREFIX}:#{kind}", JSON.generate(payload), ex: STATUS_TTL_SECONDS)
    end

    def read(key)
      raw = @redis.get(key)
      raw ? JSON.parse(raw) : {}
    rescue JSON::ParserError
      {}
    end
  end
end
