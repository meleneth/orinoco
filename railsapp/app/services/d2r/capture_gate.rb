# frozen_string_literal: true

require "json"
require "time"

module D2r
  class CaptureGate
    KEY = "orinoco:d2r:observer:capture:pending"

    def initialize(redis:, stale_after: 2.0, clock: -> { Time.now.utc })
      @redis = redis
      @stale_after = Float(stale_after)
      @clock = clock
    end

    def pending?
      pending = read
      return false unless pending

      @clock.call - Time.iso8601(pending.fetch("requested_at")) < @stale_after
    rescue JSON::ParserError, KeyError, ArgumentError
      false
    end

    def requested!(request_id)
      payload = JSON.generate("request_id" => request_id.to_s, "requested_at" => @clock.call.iso8601(6))
      @redis.set(KEY, payload, ex: [ @stale_after.ceil + 1, 1 ].max)
    end

    def complete!(request_id)
      pending = read
      @redis.del(KEY) if pending && pending["request_id"] == request_id.to_s
    rescue JSON::ParserError
      @redis.del(KEY)
    end

    private

    def read
      value = @redis.get(KEY)
      value && JSON.parse(value)
    end
  end
end
