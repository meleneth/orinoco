# frozen_string_literal: true

require "json"

module Orinoco
  module Messaging
    class QueueInspector
      ATTRIBUTE_NAMES = %w[
        ApproximateNumberOfMessages
        ApproximateNumberOfMessagesNotVisible
        ApproximateNumberOfMessagesDelayed
      ].freeze

      QueueSnapshot = Data.define(:name, :url, :arn, :visible, :in_flight, :delayed)
      MessageSnapshot = Data.define(:message_id, :body, :parsed_body, :attributes)

      def initialize(sqs:, topology:)
        @sqs = sqs
        @topology = topology
      end

      def queues
        @topology.queue_refs.map do |ref|
          attributes = @sqs.get_queue_attributes(
            queue_url: ref.url,
            attribute_names: ATTRIBUTE_NAMES
          ).attributes

          QueueSnapshot.new(
            name: ref.name,
            url: ref.url,
            arn: ref.arn,
            visible: integer_attribute(attributes, "ApproximateNumberOfMessages"),
            in_flight: integer_attribute(attributes, "ApproximateNumberOfMessagesNotVisible"),
            delayed: integer_attribute(attributes, "ApproximateNumberOfMessagesDelayed")
          )
        end
      end

      def queue(name)
        queues.find { |queue| queue.name == name.to_s }
      end

      def peek(name, limit: 10)
        ref = @topology.queue_ref(name.to_s)
        response = @sqs.receive_message(
          queue_url: ref.url,
          max_number_of_messages: limit,
          wait_time_seconds: 0,
          visibility_timeout: 0,
          attribute_names: ["All"],
          message_attribute_names: ["All"]
        )

        Array(response.messages).map do |message|
          MessageSnapshot.new(
            message_id: message.message_id,
            body: message.body,
            parsed_body: parse_body(message.body),
            attributes: message.attributes || {}
          )
        end
      end

      private

      def integer_attribute(attributes, name)
        Integer(attributes.fetch(name, 0))
      end

      def parse_body(body)
        outer = JSON.parse(body)
        if outer.is_a?(Hash) && outer["Type"] == "Notification" && outer["Message"]
          outer.merge("Message" => JSON.parse(outer["Message"]))
        else
          outer
        end
      rescue JSON::ParserError
        nil
      end
    end
  end
end