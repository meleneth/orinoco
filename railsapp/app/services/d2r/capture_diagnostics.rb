# frozen_string_literal: true

require "json"
require "time"

module D2r
  # Redis-backed operator controls and diagnostics shared across Rails and the capture worker.
  class CaptureDiagnostics
    STATUS_KEY = "orinoco:d2r:observer:capture:status"
    OVERRIDE_KEY = "orinoco:d2r:observer:capture:force_active"
    STATUS_TTL = 180

    def initialize(redis:, clock: -> { Time.now.utc })
      @redis = redis
      @clock = clock
    end

    def force_active?
      @redis.get(OVERRIDE_KEY) == "1"
    end

    def force_active=(enabled)
      enabled ? @redis.set(OVERRIDE_KEY, "1") : @redis.del(OVERRIDE_KEY)
    end

    def record(reason:, source:, active:, presence: nil, error: nil)
      previous = snapshot.fetch("worker", {})
      now = @clock.call.iso8601(6)
      worker = {
        "reason" => reason.to_s,
        "source" => source.to_s,
        "presence_active" => active,
        "last_checked_at" => now,
        "last_requested_at" => reason == :requested ? now : previous["last_requested_at"],
        "last_error" => error || (reason == :failed ? previous["last_error"] : nil),
        "presence" => presence
      }
      @redis.set(STATUS_KEY, JSON.generate(worker), ex: STATUS_TTL)
    end

    def snapshot
      raw = @redis.get(STATUS_KEY)
      { "worker" => raw ? JSON.parse(raw) : {}, "force_active" => force_active? }
    rescue JSON::ParserError
      { "worker" => {}, "force_active" => force_active? }
    end
  end
end
