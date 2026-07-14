# frozen_string_literal: true

require "json"
require "time"

module Wos
  class StatusStore
    KEY = "wos:brain:status"

    def initialize(redis:, clock: -> { Time.now.utc })
      @redis = redis
      @clock = clock
    end

    def read
      raw = @redis.get(KEY)
      return default_status if raw.nil? || raw.empty?

      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? default_status.merge(parsed) : default_status
    rescue JSON::ParserError
      default_status
    end

    def update!(attributes)
      status = read.merge(stringify_keys(attributes)).merge("updated_at" => now)
      @redis.set(KEY, JSON.generate(status))
      status
    end

    def disabled!
      update!("state" => "disabled", "last_error" => "")
    end

    def missing_source!
      update!("state" => "waiting_for_source", "last_error" => "WOSBrain screenshot source is not configured")
    end

    def capture_requested!(source_name:, request_id:)
      update!(
        "state" => "capture_requested",
        "screenshot_source_name" => source_name.to_s,
        "last_request_id" => request_id.to_s,
        "last_capture_requested_at" => now,
        "last_error" => ""
      )
    end

    def recognition_succeeded!
      update!(
        "state" => "recognized",
        "last_recognized_at" => now,
        "last_error" => ""
      )
    end

    def projection_succeeded!
      update!(
        "state" => "projected",
        "last_projected_at" => now,
        "last_error" => ""
      )
    end

    def projection_failed!(message)
      update!(
        "state" => "projection_error",
        "last_projection_failed_at" => now,
        "last_error" => message.to_s
      )
    end

    def failed!(message)
      update!("state" => "error", "last_error" => message.to_s)
    end

    private

    def default_status
      {
        "state" => "idle",
        "screenshot_source_name" => "",
        "last_request_id" => "",
        "last_capture_requested_at" => "",
        "last_recognized_at" => "",
        "last_projected_at" => "",
        "last_projection_failed_at" => "",
        "last_error" => "",
        "updated_at" => ""
      }
    end

    def now
      @clock.call.utc.iso8601(6)
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.to_s] = value
      end
    end
  end
end
