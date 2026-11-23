# frozen_string_literal: true

module D2r
  class ScreenshotRequestLoop
    DEFAULT_INTERVAL_SECONDS = 0.5
    DEFAULT_IMAGE_WIDTH = 640
    DEFAULT_IMAGE_HEIGHT = 400
    DEFAULT_IMAGE_QUALITY = 70

    def initialize(config_reader:, publisher:, gate:, bridge_available: -> { true }, sleeper: ->(seconds) { sleep seconds }, logger: ->(message) { warn message })
      @config_reader = config_reader
      @publisher = publisher
      @gate = gate
      @bridge_available = bridge_available
      @sleeper = sleeper
      @logger = logger
      @interval_seconds = DEFAULT_INTERVAL_SECONDS
    end

    def run(stop: -> { false })
      until stop.call
        run_once
        @sleeper.call(@interval_seconds)
      end
    end

    def run_once
      config = @config_reader.call
      return :disabled unless config.enabled?

      source_name = config.screenshot_source_name.to_s.strip
      return :missing_source if source_name.empty?
      return :waiting_for_obs_bridge unless @bridge_available.call
      return :in_flight if @gate.pending?

      settings = config.config
      @interval_seconds = Float(settings.fetch("interval_seconds", DEFAULT_INTERVAL_SECONDS))

      event = @publisher.publish!(
        source_name: source_name,
        image_format: "jpg",
        width: Integer(settings.fetch("image_width", DEFAULT_IMAGE_WIDTH)),
        height: Integer(settings.fetch("image_height", DEFAULT_IMAGE_HEIGHT)),
        quality: Integer(settings.fetch("jpeg_quality", DEFAULT_IMAGE_QUALITY))
      )
      @gate.requested!(event.correlation.fetch("request_id"))
      :requested
    rescue StandardError => e
      @logger.call("[d2r/capture] #{e.class}: #{e.message}")
      :failed
    end
  end
end
