# frozen_string_literal: true

require "base64"
require "tempfile"
require_relative "fast_classifier"
require_relative "hud_reader"
require_relative "hud_area_reader"
require_relative "hud_tracker"
require_relative "loot_tracker"
require_relative "ground_label_reader"
require_relative "state_tracker"

module D2r
  class ScreenshotEventHandler
    DATA_URI_PATTERN = %r{\Adata:image/(?<format>[a-zA-Z0-9.+-]+);base64,(?<data>.+)\z}m

    def initialize(config_reader:, classifier: FastClassifier.new, tracker: StateTracker.new,
      hud_reader: HudReader.new, hud_area_reader: HudAreaReader.new, hud_tracker: HudTracker.new,
      ground_label_reader: GroundLabelReader.new, loot_tracker: LootTracker.new, gate: nil)
      @config_reader = config_reader
      @classifier = classifier
      @tracker = tracker
      @hud_reader = hud_reader
      @hud_area_reader = hud_area_reader
      @hud_tracker = hud_tracker
      @ground_label_reader = ground_label_reader
      @loot_tracker = loot_tracker
      @gate = gate
    end

    def call(event, context)
      config = @config_reader.call
      return :disabled unless config.enabled?

      source_name = config.screenshot_source_name.to_s.strip
      return :missing_source if source_name.empty?
      return :ignored_source unless event.payload_value("sourceName").to_s == source_name

      classification, hud, loot = with_screenshot_file(event.payload) do |path|
        result = @classifier.call(path).to_h
        hud_reading = @hud_reader.call(path)
        # Bitmap references are approximate and can map an unseen Tower label
        # to the nearest Catacombs fixture. A known OCR area is stronger direct
        # evidence and must override that nearest-reference guess.
        inferred_area = @hud_area_reader.call(path)
        hud_reading["area"] = inferred_area if inferred_area
        screen = result.dig("signals", "screen", "state")
        left_panel = result.dig("signals", "left_panel", "state")
        right_panel = result.dig("signals", "right_panel", "state")
        tooltip = result.dig("signals", "tooltip", "state")
        suppress_labels = %w[loading_screen character_select character_creation death_screen].include?(screen) ||
          %w[stash_runes stash_other].include?(left_panel) || right_panel == "inventory" ||
          (tooltip && tooltip != "none" && tooltip != "unknown")
        labels = if suppress_labels
          []
        else
          @ground_label_reader.call(path)
        end
        [ result, hud_reading, labels ]
      end
      events = @tracker.observe(classification, observed_at: event.occurred_at)
      events.concat(@hud_tracker.observe(hud, observed_at: event.occurred_at))
      events.concat(@loot_tracker.observe(loot, observed_at: event.occurred_at))
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
