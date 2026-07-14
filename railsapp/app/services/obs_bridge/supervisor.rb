# frozen_string_literal: true

module ObsBridge
  class Supervisor
    def initialize(
      state:,
      control_consumer:,
      command_consumer:,
      runtime_factory:,
      signal_queue:,
      logger: nil,
      idle_sleep: 0.1
    )
      @state = state
      @control_consumer = control_consumer
      @command_consumer = command_consumer
      @runtime_factory = runtime_factory
      @signal_queue = signal_queue
      @logger = logger || ->(msg) { warn msg }
      @idle_sleep = idle_sleep

      @mutex = Mutex.new
      @stop_requested = false
      @running = false
      @control_thread = nil
      @command_thread = nil
      @runtime = nil
    end

    def run
      @mutex.synchronize do
        raise "supervisor already running" if @running

        @stop_requested = false
        @running = true
      end

      start_control_thread!
      start_command_thread!
      reconcile_runtime!

      until stop_requested?
        drain_signals
        sleep @idle_sleep
      end
    ensure
      shutdown_runtime
      join_command_thread
      join_control_thread
      @mutex.synchronize { @running = false }
    end

    def stop!
      @mutex.synchronize do
        @stop_requested = true
      end
    end

    def running?
      @mutex.synchronize { @running }
    end

    private

    def start_control_thread!
      @control_thread = Thread.new do
        with_failure("control consumer", stop_supervisor: true) do
          @control_consumer.run(stop: -> { stop_requested? })
        end
      end
    end

    def start_command_thread!
      @command_thread = Thread.new do
        with_failure("command consumer", stop_supervisor: true) do
          @command_consumer.run(
            stop: -> { stop_requested? },
            dispatch: ->(request) { enqueue_obs_request!(request) }
          )
        end
      end
    end

    def join_control_thread
      thread = @control_thread
      return unless thread

      thread.join(1)
      @control_thread = nil
    end

    def join_command_thread
      thread = @command_thread
      return unless thread

      thread.join(1)
      @command_thread = nil
    end

    def drain_signals
      loop do
        handle_signal(@signal_queue.pop(true))
      rescue ThreadError
        break
      end
    end

    def handle_signal(signal)
      case signal
      when Cmd::Reconcile
        reconcile_runtime!
      when Cmd::RefreshInventory
        refresh_inventory!
      when Hash
        enqueue_obs_request!(signal)
      else
        @logger.call("[obs-bridge/supervisor] ignoring unknown signal #{signal.inspect}")
      end
    end

    def reconcile_runtime!
      @state.desired_enabled? ? start_runtime_unless_running! : stop_runtime_if_running!
    end

    def start_runtime_unless_running!
      return if runtime_running?

      @logger.call("[obs-bridge/supervisor] starting runtime")

      with_failure("runtime start", clear_runtime: true) do
        @runtime = @runtime_factory.call
        @runtime.start!
      end
    end

    def stop_runtime_if_running!
      with_running_runtime("runtime stop", clear_runtime: true) do |runtime|
        @logger.call("[obs-bridge/supervisor] stopping runtime")
        runtime.stop!
      end
    end

    def refresh_inventory!
      with_running_runtime("inventory refresh") do |runtime|
        @logger.call("[obs-bridge/supervisor] refreshing inventory")
        runtime.refresh_inventory!
      end
    end

    def enqueue_obs_request!(request)
      with_running_runtime("obs request enqueue") do |runtime|
        runtime.enqueue_obs_request!(request)
      end
    end

    def shutdown_runtime
      with_running_runtime("runtime shutdown", clear_runtime: true) do |runtime|
        runtime.stop!
      end
    end

    def with_running_runtime(action, clear_runtime: false)
      runtime = @runtime
      return unless runtime&.running?

      with_failure(action, clear_runtime: clear_runtime) do
        yield runtime
      end
    end

    def with_failure(action, clear_runtime: false, stop_supervisor: false)
      yield
    rescue StandardError => e
      @runtime = nil if clear_runtime
      report_failure(action, e)
      stop! if stop_supervisor
    end

    def report_failure(action, error)
      message = "#{action} failed: #{error.class}: #{error.message}"
      @state.set_last_error!(message)
      @logger.call("[obs-bridge/supervisor] #{message}")
    end

    def runtime_running?
      @runtime&.running? || false
    end

    def stop_requested?
      @mutex.synchronize { @stop_requested }
    end
  end
end
