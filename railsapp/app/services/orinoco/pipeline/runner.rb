# frozen_string_literal: true

module Orinoco
  module Pipeline
    class Runner
      def initialize(definition:, sqs:, sns:, topology:, logger: nil)
        @definition = definition
        @sqs = sqs
        @sns = sns
        @topology = topology
        @logger = logger || ->(message) { warn message }
        @stop_requested = false
        @failure = nil
        @mutex = Mutex.new
      end

      def run
        install_signal_handlers

        threads = consumers.map do |consumer|
          Thread.new { run_consumer(consumer) }
        end

        sleep 0.1 until stop_requested?
      ensure
        context.stop_runtime
        @mutex.synchronize { @stop_requested = true }
        threads&.each { |thread| thread.join(1) }
        raise @failure if @failure
      end

      def run_once
        consumers.each(&:run_once)
      end

      def context
        @context ||= Context.new(
          publisher: Publisher.new(sns: @sns, topology: @topology, default_topic: @definition.default_topic),
          runtime_factory: @definition.runtime_block,
          logger: @logger
        )
      end

      private

      def run_consumer(consumer)
        consumer.run(stop: -> { stop_requested? })
      rescue StandardError => e
        @logger.call("[pipeline/#{@definition.name}] consumer thread failed: #{e.class}: #{e.message}")
        @mutex.synchronize do
          @failure ||= e
          @stop_requested = true
        end
      end

      def consumers
        @consumers ||= @definition.consumes.map do |consume|
          SqsConsumer.new(
            sqs: @sqs,
            queue_url: @topology.queue_url(consume.queue_name),
            definition: @definition,
            context: context,
            logger: @logger,
            wait_time_seconds: consume.wait_time_seconds,
            max_number_of_messages: consume.max_number_of_messages
          )
        end
      end

      def install_signal_handlers
        %w[INT TERM].each do |signal|
          Signal.trap(signal) { @stop_requested = true }
        end
      end

      def stop_requested?
        @mutex.synchronize { @stop_requested }
      end
    end
  end
end
