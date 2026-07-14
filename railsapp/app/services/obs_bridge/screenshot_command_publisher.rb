# frozen_string_literal: true

require "json"
require "securerandom"
require_relative "../orinoco/pipeline"
require_relative "../orinoco/messaging/names"

module ObsBridge
  class ScreenshotCommandPublisher
    def initialize(sns:, topology:, uuid_generator: -> { SecureRandom.uuid })
      @publisher = Orinoco::Pipeline::Publisher.new(
        sns: sns,
        topology: topology,
        default_topic: Orinoco::Messaging::Names::OBS_COMMAND_TOPIC
      )
      @uuid_generator = uuid_generator
    end

    def publish!(source_name: nil, scene_name: nil, image_format: "png", width: nil, height: nil, quality: nil, reply_topic: Orinoco::Messaging::Names::OBS_SCREENSHOT_RESULT_TOPIC, request_id: nil)
      request_id ||= @uuid_generator.call
      request_data = {
        "imageFormat" => image_format
      }
      request_data["imageWidth"] = Integer(width) if positive_integer?(width)
      request_data["imageHeight"] = Integer(height) if positive_integer?(height)
      request_data["imageCompressionQuality"] = Integer(quality) if non_negative_integer?(quality)
      request_data["sourceName"] = source_name if present?(source_name)
      request_data["sceneName"] = scene_name if present?(scene_name)

      @publisher.publish(
        "obs.command.requested",
        {
          "request" => {
            "requestType" => "GetSourceScreenshot",
            "requestData" => request_data
          },
          "reply_topic" => reply_topic
        },
        source: "obs.screenshot.requester",
        correlation: { "request_id" => request_id }
      )
    end

    private

    def positive_integer?(value)
      !value.nil? && Integer(value).positive?
    rescue ArgumentError, TypeError
      false
    end

    def non_negative_integer?(value)
      !value.nil? && Integer(value) >= 0
    rescue ArgumentError, TypeError
      false
    end

    def present?(value)
      !value.nil? && !value.to_s.strip.empty?
    end
  end
end
