# frozen_string_literal: true

module D2r
  class ScreenshotRequestLoop
    DEFAULT_INTERVAL_SECONDS = 0.5
    DEFAULT_IDLE_INTERVAL_SECONDS = 60.0
    DEFAULT_IMAGE_WIDTH = 640
    DEFAULT_IMAGE_HEIGHT = 400
    DEFAULT_IMAGE_QUALITY = 70

    def initialize(config_reader:, publisher:, gate:, presence: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, bridge_available: -> { true }, observer_control: nil, sleeper: ->(seconds) { sleep seconds }, logger: ->(message) { warn message })
      @config_reader = config_reader
      @publisher = publisher
      @gate = gate
      @presence = presence
      @observer_control = observer_control
      @clock = clock
      @last_request_at = nil
      @last_source = nil
      @bridge_available = bridge_available
      @sleeper = sleeper
      @logger = logger
      @interval_seconds = DEFAULT_INTERVAL_SECONDS
    end

    def run(stop: -> { false })
      until stop.call
        run_once
        yield if block_given?
        @sleeper.call(@interval_seconds)
      end
    end

    def run_once
      config = @config_reader.call
      @interval_seconds = DEFAULT_INTERVAL_SECONDS
      return decision(:disabled, "") unless config.enabled?
      source_name = config.screenshot_source_name.to_s.strip
      mode = @observer_control&.mode || "auto"
      return decision(:force_off, source_name) if mode == "force_off"
      return decision(:missing_source, source_name) if source_name.empty?

      settings = config.config
      @interval_seconds = Float(settings.fetch("interval_seconds", DEFAULT_INTERVAL_SECONDS))
      active = mode == "force_on" || !@presence || @presence.active?(source_name)
      idle_interval = Float(settings.fetch("idle_interval_seconds", DEFAULT_IDLE_INTERVAL_SECONDS)).clamp(60.0, 300.0)
      now = @clock.call
      if !active && @last_source == source_name && @last_request_at && now - @last_request_at < idle_interval
        return decision(:standby, source_name)
      end
      return decision(:waiting_for_obs_bridge, source_name) unless @bridge_available.call
      return decision(:in_flight, source_name) if @gate.pending?

      event = @publisher.publish!(
        source_name: source_name,
        image_format: "jpg",
        width: Integer(settings.fetch("image_width", DEFAULT_IMAGE_WIDTH)),
        height: Integer(settings.fetch("image_height", DEFAULT_IMAGE_HEIGHT)),
        quality: Integer(settings.fetch("jpeg_quality", DEFAULT_IMAGE_QUALITY))
      )
      @gate.requested!(event.correlation.fetch("request_id"))
      @last_request_at = now
      @last_source = source_name
      decision(:requested, source_name)
    rescue StandardError => e
      @logger.call("[d2r/capture] #{e.class}: #{e.message}")
      @observer_control&.record_capture(reason: :failed, source: source_name, error: "#{e.class}: #{e.message}")
      :failed
    end

    private

    def decision(reason, source)
      @observer_control&.record_capture(reason:, source:)
      reason
    end
  end
end
