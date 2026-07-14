# frozen_string_literal: true

require "json"

module Orinoco
  module Messaging
    class AwsMessage
      class InvalidPayload < StandardError; end

      def self.unwrap(sqs_message)
        unwrap_body(sqs_message.body)
      end

      def self.unwrap_body(body)
        outer = parse_json!(body)

        if outer.is_a?(Hash) && outer["Type"] == "Notification" && outer["Message"]
          parse_json!(outer["Message"])
        else
          outer
        end
      end

      def self.parse_json!(value)
        JSON.parse(value)
      rescue JSON::ParserError => e
        raise InvalidPayload, "invalid JSON payload: #{e.message}"
      end

      private_class_method :parse_json!
    end
  end
end