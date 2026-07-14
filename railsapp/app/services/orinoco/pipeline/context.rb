# frozen_string_literal: true

module Orinoco
  module Pipeline
    class Context
      def initialize(publisher:, runtime_factory: nil, logger: nil)
        @publisher = publisher
        @runtime_factory = runtime_factory
        @logger = logger || ->(message) { warn message }
        @mutex = Mutex.new
        @runtime = nil
      end

      def publish(type, payload = {}, **options)
        @publisher.publish(type, payload, **options)
      end

      def start_runtime
        @mutex.synchronize do
          return @runtime if runtime_running_locked?
          raise "runtime block not configured" unless @runtime_factory

          @runtime = @runtime_factory.call(self)
          @runtime.start! if @runtime.respond_to?(:start!)
          @runtime
        end
      end

      def stop_runtime
        runtime = nil
        @mutex.synchronize do
          runtime = @runtime
          @runtime = nil
        end

        runtime&.stop! if runtime.respond_to?(:stop!)
        runtime
      end

      def with_runtime
        runtime = @mutex.synchronize { @runtime }
        return nil unless runtime

        yield runtime
      end

      def runtime_running?
        @mutex.synchronize { runtime_running_locked? }
      end

      def logger
        @logger
      end

      private

      def runtime_running_locked?
        @runtime && (!@runtime.respond_to?(:running?) || @runtime.running?)
      end
    end
  end
end