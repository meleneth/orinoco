# frozen_string_literal: true

module Orinoco
  module Pipeline
    class Definition
      Consume = Struct.new(:queue_name, :wait_time_seconds, :max_number_of_messages, keyword_init: true)

      attr_reader :name, :consumes, :handlers, :default_topic, :runtime_block

      def initialize(name)
        @name = name.to_sym
        @consumes = []
        @handlers = {}
        @default_topic = nil
        @runtime_block = nil
      end

      def consume(queue_name, wait_time_seconds: 20, max_number_of_messages: 10)
        @consumes << Consume.new(
          queue_name: queue_name,
          wait_time_seconds: wait_time_seconds,
          max_number_of_messages: max_number_of_messages
        )
      end

      def publish_to(topic_name)
        @default_topic = topic_name
      end

      def on(event_type, &block)
        raise ArgumentError, "handler block required" unless block_given?

        @handlers[event_type.to_s] = block
      end

      def runtime(&block)
        raise ArgumentError, "runtime block required" unless block_given?

        @runtime_block = block
      end

      def handle(event, context)
        handler = @handlers[event.type]
        return false unless handler

        handler.call(event, context)
        true
      end
    end
  end
end