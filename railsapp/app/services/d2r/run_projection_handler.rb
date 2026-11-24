# frozen_string_literal: true

require "timeout"
require_relative "run_projection"
require_relative "character_archive"

module D2r
  class RunProjectionHandler
    STREAM = :d2r_events
    TARGET = "d2r_live_projection"
    BROADCAST_TIMEOUT_SECONDS = 5

    def initialize(projection:, archive: D2r::RunArchive.new, broadcaster: Turbo::StreamsChannel, logger: Rails.logger, broadcast_timeout_seconds: BROADCAST_TIMEOUT_SECONDS)
      @projection = projection
      @archive = archive
      @broadcaster = broadcaster
      @logger = logger
      @broadcast_timeout_seconds = broadcast_timeout_seconds
    end

    def call(event)
      before = @projection.snapshot.slice(*D2rLiveProjectionComponent::FIELDS)
      state = @projection.call(event)
      @archive.call(event, state)
      D2r::CharacterArchive.new.call(event, state) if event.type.start_with?("d2r.character.") || event.type == "d2r.level.changed"
      broadcast_state(state) if before != state.slice(*D2rLiveProjectionComponent::FIELDS)
      state
    end

    private

    def broadcast_state(state)
      Timeout.timeout(@broadcast_timeout_seconds) do
        Rails.application.reloader.wrap do
          @broadcaster.broadcast_replace_to(
            STREAM,
            target: TARGET,
            layout: false,
            renderable: D2rLiveProjectionComponent.new(state: state)
          )
        end
      end
    rescue StandardError => e
      @logger.warn("[d2r-run-projection] broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
