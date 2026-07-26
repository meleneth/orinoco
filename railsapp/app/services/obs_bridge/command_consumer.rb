# frozen_string_literal: true

require "json"
require_relative "../orinoco/pipeline"

module ObsBridge
  class CommandConsumer
    def initialize(
      sqs:,
      queue_url:,
      signal_queue:,
      logger: nil,
      wait_time_seconds: 20,
      max_number_of_messages: 10
    )
      @sqs = sqs
      @queue_url = queue_url
      @signal_queue = signal_queue
      @logger = logger || ->(msg) { warn msg }
      @wait_time_seconds = wait_time_seconds
      @max_number_of_messages = max_number_of_messages
    end

    def run(stop:, dispatch: nil)
      until stop.call
        receive_messages.each do |message|
          request = decode_message_body(message.body)
          @logger.call("[obs-bridge/command-consumer] received #{command_label(request)}")
          if dispatch_command(request, dispatch)
            delete_message(message)
          elsif disposable_command?(request)
            @logger.call("[obs-bridge/command-consumer] runtime unavailable; dropping stale #{command_label(request)}")
            delete_message(message)
          else
            @logger.call("[obs-bridge/command-consumer] runtime unavailable; leaving #{command_label(request)} on queue")
          end
        rescue StandardError => e
          @logger.call("[obs-bridge/command-consumer] failed to process message: #{e.class}: #{e.message}")
        end
      end
    end

    private

    def dispatch_command(request, dispatch)
      return dispatch.call(request) if dispatch

      @signal_queue << request
      true
    end

    def receive_messages
      response = @sqs.receive_message(
        queue_url: @queue_url,
        wait_time_seconds: @wait_time_seconds,
        max_number_of_messages: @max_number_of_messages
      )

      Array(response.messages)
    end

    def delete_message(message)
      @sqs.delete_message(
        queue_url: @queue_url,
        receipt_handle: message.receipt_handle
      )
    end

    def decode_message_body(body)
      parsed = Orinoco::Messaging::AwsMessage.unwrap_body(body)

      command =
        if parsed.is_a?(Hash) && parsed.key?("type")
          event = Orinoco::Pipeline::Event.from_hash(parsed)
          raise ArgumentError, "expected obs.command.requested event" unless event.type == "obs.command.requested"

          build_command_from_event(event)
        else
          parsed
        end

      request = command.is_a?(Hash) && command.key?("request") ? command.fetch("request") : command
      raise ArgumentError, "expected OBS request hash" unless request.is_a?(Hash)

      command
    end

    def build_command_from_event(event)
      payload = event.payload
      command = {
        "request" => payload.fetch("request"),
        "source" => event.source,
        "occurred_at" => event.occurred_at,
        "correlation" => event.correlation.merge(payload.fetch("correlation", {}))
      }
      command["reply_topic"] = payload["reply_topic"] || payload["replyTopic"] if payload["reply_topic"] || payload["replyTopic"]
      command
    end

    def disposable_command?(command)
      request = command.is_a?(Hash) && command.key?("request") ? command.fetch("request") : command
      return false unless request.is_a?(Hash)

      request["requestType"] == "GetSourceScreenshot"
    end

    def command_label(command)
      request = command.is_a?(Hash) && command.key?("request") ? command.fetch("request") : command
      request_type = request.is_a?(Hash) ? request["requestType"] : nil
      source = command.is_a?(Hash) ? command["source"] : nil

      [ source, request_type ].compact.join(" ")
    end
  end
end
