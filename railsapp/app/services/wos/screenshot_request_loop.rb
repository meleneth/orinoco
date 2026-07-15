# frozen_string_literal: true

module Wos
  class ScreenshotRequestLoop
    DEFAULT_INTERVAL_SECONDS = 5.0
    DEFAULT_IMAGE_WIDTH = 1280
    DEFAULT_IMAGE_HEIGHT = 720

    def initialize(
      config_reader:,
      publisher:,
      status_store:,
      bridge_available: -> { true },
      interval_seconds: DEFAULT_INTERVAL_SECONDS,
      image_width: DEFAULT_IMAGE_WIDTH,
      image_height: DEFAULT_IMAGE_HEIGHT,
      sleeper: ->(seconds) { sleep seconds },
      logger: ->(message) { warn message }
    )
      @config_reader = config_reader
      @publisher = publisher
      @status_store = status_store
      @bridge_available = bridge_available
      @interval_seconds = Float(interval_seconds)
      @image_width = Integer(image_width)
      @image_height = Integer(image_height)
      @sleeper = sleeper
      @logger = logger
    end

    def run(stop: -> { false })
      until stop.call
        run_once
        @sleeper.call(@interval_seconds)
      end
    end

    def run_once
      config = @config_reader.call
      return @status_store.disabled! unless config.enabled?

      source_name = config.screenshot_source_name.to_s.strip
      return @status_store.missing_source! if source_name.empty?
      return @status_store.waiting_for_obs_bridge! unless @bridge_available.call

      event = @publisher.publish!(
        source_name: source_name,
        width: @image_width,
        height: @image_height
      )
      request_id = event.correlation.fetch("request_id", "")
      @status_store.capture_requested!(source_name: source_name, request_id: request_id)
    rescue StandardError => e
      message = "WOSBrain screenshot request failed: #{e.class}: #{e.message}"
      @logger.call("[wos-brain/capture] #{message}")
      @status_store.failed!(message)
    end
  end
end
