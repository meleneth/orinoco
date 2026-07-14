# frozen_string_literal: true

require_relative "../orinoco/pipeline"

module ObsBridge
  class ControlConsumer
    def initialize(
      sqs:,
      queue_url:,
      bridge_id:,
      applier:,
      logger: nil,
      wait_time_seconds: 20,
      max_number_of_messages: 1,
      message_unwrapper: AwsMessage,
      message_parser: ControlMessage
    )
      @sqs = sqs
      @queue_url = queue_url
      @bridge_id = bridge_id
      @applier = applier
      @logger = logger || ->(msg) { warn msg }
      @wait_time_seconds = wait_time_seconds
      @max_number_of_messages = max_number_of_messages
      @message_unwrapper = message_unwrapper
      @message_parser = message_parser
    end

    def run(stop: -> { false })
      loop do
        break if stop.call

        run_once
      end
    end

    def run_once
      response = @sqs.receive_message(
        queue_url: @queue_url,
        max_number_of_messages: @max_number_of_messages,
        wait_time_seconds: @wait_time_seconds
      )

      Array(response.messages).each do |message|
        process_message(message)
      end
    end

    def process_message(message)
      @logger.call("[obs-bridge/control] message: #{message.class}: #{message.body}")

      payload = @message_unwrapper.unwrap(message)
      control_payload = normalize_control_payload(payload)
      control_message = @message_parser.parse(control_payload, expected_bridge_id: @bridge_id)
      result = @applier.apply(control_message)

      delete_message(message)
      result
    rescue AwsMessage::InvalidPayload, ControlMessage::Invalid => e
      @logger.call("[obs-bridge/control] invalid message left for retry: #{e.class}: #{e.message}")
      :failed
    rescue StandardError => e
      @logger.call("[obs-bridge/control] processing failed: #{e.class}: #{e.message}")
      :failed
    end

    private

    def normalize_control_payload(payload)
      return payload unless payload.is_a?(Hash) && payload.key?("type") && payload.key?("payload")

      event = Orinoco::Pipeline::Event.from_hash(payload)
      event.payload.merge("type" => event.type)
    end

    def delete_message(message)
      @sqs.delete_message(
        queue_url: @queue_url,
        receipt_handle: message.receipt_handle
      )
    end
  end
end
