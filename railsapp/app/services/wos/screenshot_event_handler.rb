# frozen_string_literal: true

require "base64"
require "tempfile"
require_relative "ruleset_resolver"
require_relative "screenshot_recognizer"

module Wos
  class ScreenshotEventHandler
    DATA_URI_PATTERN = %r{\Adata:image/(?<format>[a-zA-Z0-9.+-]+);base64,(?<data>.+)\z}m

    def initialize(config_reader:, recognizer_factory: nil, status_store: nil)
      @config_reader = config_reader
      @recognizer_factory = recognizer_factory || method(:default_recognizer)
      @status_store = status_store
    end

    def call(event, context)
      config = @config_reader.call
      return :disabled unless enabled?(config)
      return :ignored_source unless source_matches?(config, event)

      with_screenshot_file(event.payload) do |path|
        result = @recognizer_factory.call(config).call(path)
        context.publish(
          "wos.board.recognized",
          recognized_payload(event: event, result: result),
          correlation: event.correlation
        )
        @status_store&.recognition_succeeded!
      end

      :recognized
    rescue StandardError => e
      @status_store&.failed!("WOSBrain recognition failed: #{e.class}: #{e.message}")
      raise
    end

    private

    def default_recognizer(config)
      Wos::ScreenshotRecognizer.new(
        ruleset_resolver: Wos::RulesetResolver.new(config: config)
      )
    end

    def enabled?(config)
      if config.respond_to?(:enabled?)
        config.enabled?
      else
        ActiveModel::Type::Boolean.new.cast((config || {}).fetch("enabled", false))
      end
    end

    def source_matches?(config, event)
      configured_source = if config.respond_to?(:screenshot_source_name)
        config.screenshot_source_name
      else
        (config || {})["screenshot_source_name"]
      end.to_s.strip

      configured_source.empty? || event.payload_value("sourceName").to_s == configured_source
    end

    def with_screenshot_file(payload)
      image_data = payload.fetch("imageData")
      format = payload.fetch("imageFormat", "png").to_s
      decoded = decode_image_data(image_data)

      Tempfile.create(["wos-screenshot-", ".#{format}"]) do |file|
        file.binmode
        file.write(decoded)
        file.flush
        yield file.path
      end
    end

    def decode_image_data(image_data)
      raw = image_data.to_s
      encoded = raw[DATA_URI_PATTERN, :data] || raw
      Base64.strict_decode64(encoded)
    rescue ArgumentError => e
      raise ArgumentError, "invalid screenshot imageData: #{e.message}"
    end

    def recognized_payload(event:, result:)
      {
        "screenshot" => {
          "sourceName" => event.payload_value("sourceName"),
          "activeSceneName" => event.payload_value("activeSceneName"),
          "imageFormat" => event.payload_value("imageFormat"),
          "captureStartedAt" => event.payload_value("captureStartedAt"),
          "captureCompletedAt" => event.payload_value("captureCompletedAt"),
          "captureDurationMs" => event.payload_value("captureDurationMs")
        }.compact,
        "recognition" => stringify_keys(result.to_h)
      }
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, inner_value), result|
          result[key.to_s] = stringify_keys(inner_value)
        end
      when Array
        value.map { |entry| stringify_keys(entry) }
      else
        value
      end
    end
  end
end