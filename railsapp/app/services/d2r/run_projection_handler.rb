# frozen_string_literal: true

require "timeout"
require_relative "run_projection"

module D2r
  class RunProjectionHandler
    STREAM = :d2r_events
    TARGET = "d2r_event_feed"
    BROADCAST_TIMEOUT_SECONDS = 5

    def initialize(projection:, archive: D2r::RunArchive.new, broadcaster: Turbo::StreamsChannel, logger: Rails.logger, broadcast_timeout_seconds: BROADCAST_TIMEOUT_SECONDS)
      @projection = projection
      @archive = archive
      @broadcaster = broadcaster
      @logger = logger
      @broadcast_timeout_seconds = broadcast_timeout_seconds
    end

    def call(event)
      state = @projection.call(event)
      @archive.call(event, state)
      broadcast_events(state.fetch("events")) unless event.type == "d2r.state.changed"
      state
    end

    private

    def broadcast_events(events)
      Timeout.timeout(@broadcast_timeout_seconds) do
        Rails.application.reloader.wrap do
          @broadcaster.broadcast_update_to(
            STREAM,
            target: TARGET,
            layout: false,
            renderable: D2rEventFeedComponent.new(events: events)
          )
        end
      end
    rescue StandardError => e
      @logger.warn("[d2r-run-projection] broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
