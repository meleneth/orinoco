# frozen_string_literal: true

require "base64"
require "tempfile"
require_relative "fast_classifier"
require_relative "state_tracker"

module D2r
  class ScreenshotEventHandler
    DATA_URI_PATTERN = %r{\Adata:image/(?<format>[a-zA-Z0-9.+-]+);base64,(?<data>.+)\z}m

    def initialize(config_reader:, classifier: FastClassifier.new, tracker: StateTracker.new, gate: nil)
      @config_reader = config_reader
      @classifier = classifier
      @tracker = tracker
      @gate = gate
    end

    def call(event, context)
      config = @config_reader.call
      return :disabled unless config.enabled?

      source_name = config.screenshot_source_name.to_s.strip
      return :missing_source if source_name.empty?
      return :ignored_source unless event.payload_value("sourceName").to_s == source_name

      classification = with_screenshot_file(event.payload) { |path| @classifier.call(path).to_h }
      events = @tracker.observe(classification, observed_at: event.occurred_at)
      events.each do |change|
        context.publish(
          change.fetch("type"),
          change.fetch("payload").merge(
            "screenshot" => screenshot_metadata(event),
            "classification" => classification.fetch("signals")
          ),
          correlation: event.correlation
        )
      end
      events.empty? ? :unchanged : :changed
    ensure
      @gate&.complete!(event.correlation["request_id"])
    end

    private

    def with_screenshot_file(payload)
      format = payload.fetch("imageFormat", "jpg").to_s
      bytes = decode_image_data(payload.fetch("imageData"))
      Tempfile.create([ "d2r-observer-", ".#{format}" ]) do |file|
        file.binmode
        file.write(bytes)
        file.flush
        yield file.path
      end
    end

    def decode_image_data(value)
      raw = value.to_s
      encoded = raw[DATA_URI_PATTERN, :data] || raw
      Base64.strict_decode64(encoded)
    rescue ArgumentError => e
      raise ArgumentError, "invalid screenshot imageData: #{e.message}"
    end

    def screenshot_metadata(event)
      %w[sourceName activeSceneName imageFormat imageWidth imageHeight captureStartedAt captureCompletedAt captureDurationMs].to_h do |key|
        [ key, event.payload_value(key) ]
      end.compact
    end
  end
end
