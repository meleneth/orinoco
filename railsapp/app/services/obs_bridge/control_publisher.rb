# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require_relative "../orinoco/pipeline"

module ObsBridge
  class ControlPublisher
    def initialize(
      sqs:,
      queue_url:,
      bridge_id:,
      event_prefix: "obs.bridge",
      source: "obs.bridge.control",
      clock: -> { Time.now.utc },
      uuid_generator: -> { SecureRandom.uuid }
    )
      @sqs = sqs
      @queue_url = queue_url
      @bridge_id = bridge_id
      @event_prefix = event_prefix
      @source = source
      @clock = clock
      @uuid_generator = uuid_generator
    end

    def start!
      publish!("#{@event_prefix}.enable")
    end

    def stop!
      publish!("#{@event_prefix}.disable")
    end

    def refresh!
      publish!("#{@event_prefix}.refresh")
    end

    def capture_all!(duration_seconds: 900)
      seconds = Integer(duration_seconds)
      raise ArgumentError, "duration_seconds must be positive" unless seconds.positive?

      publish!("#{@event_prefix}.capture_all", duration_seconds: seconds)
    end

    private

    def publish!(type, extra = {})
      payload = {
        bridge_id: @bridge_id,
        command_id: @uuid_generator.call,
        requested_at: @clock.call.utc.iso8601(6)
      }.merge(extra)

      event = Orinoco::Pipeline::Event.build(
        type,
        payload,
        source: @source,
        occurred_at: @clock.call.utc.iso8601(6)
      )

      @sqs.send_message(
        queue_url: @queue_url,
        message_body: JSON.generate(event.to_h)
      )

      event.to_h
    end
  end
end