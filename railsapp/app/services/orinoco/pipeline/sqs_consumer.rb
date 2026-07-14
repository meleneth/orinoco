# frozen_string_literal: true

module Orinoco
  module Pipeline
    class SqsConsumer
      def initialize(sqs:, queue_url:, definition:, context:, message_unwrapper: Orinoco::Messaging::AwsMessage, logger: nil, wait_time_seconds: 20, max_number_of_messages: 10)
        @sqs = sqs
        @queue_url = queue_url
        @definition = definition
        @context = context
        @message_unwrapper = message_unwrapper
        @logger = logger || ->(message) { warn message }
        @wait_time_seconds = wait_time_seconds
        @max_number_of_messages = max_number_of_messages
      end

      def run(stop: -> { false })
        until stop.call
          run_once
        end
      end

      def run_once
        receive_messages.each do |message|
          process_message(message)
        end
      end

      def process_message(message)
        event = Event.from_hash(@message_unwrapper.unwrap(message))
        handled = @definition.handle(event, @context)
        return :unhandled unless handled

        delete_message(message)
        event.handled!
        :handled
      rescue Orinoco::Messaging::AwsMessage::InvalidPayload, Event::Invalid => e
        @logger.call("[pipeline/#{@definition.name}] invalid message left for retry: #{e.class}: #{e.message}")
        :failed
      rescue StandardError => e
        @logger.call("[pipeline/#{@definition.name}] handler failed; message left for retry: #{e.class}: #{e.message}")
        :failed
      end

      private

      def receive_messages
        response = @sqs.receive_message(
          queue_url: @queue_url,
          wait_time_seconds: @wait_time_seconds,
          max_number_of_messages: @max_number_of_messages
        )

        Array(response.messages)
      end

      def delete_message(message)
        @sqs.delete_message(queue_url: @queue_url, receipt_handle: message.receipt_handle)
      end
    end
  end
end