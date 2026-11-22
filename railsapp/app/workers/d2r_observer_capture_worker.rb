# frozen_string_literal: true

require_relative "../services/d2r/capture_gate"
require_relative "../services/d2r/screenshot_request_loop"
require_relative "../services/obs_bridge/screenshot_command_publisher"
require_relative "../services/obs_bridge/status_reader"

class D2rObserverCaptureWorker
  BRIDGE_HEARTBEAT_STALE_AFTER_SECONDS = 15

  def run
    install_signal_handlers
    loop_service.run(stop: -> { @stop_requested })
  end

  def run_once
    loop_service.run_once
  end

  private

  def loop_service
    @loop_service ||= D2r::ScreenshotRequestLoop.new(
      config_reader: -> { AffordanceConfig.fetch!(:d2r_observer) },
      publisher: screenshot_publisher,
      gate: gate,
      bridge_available: -> { obs_bridge_connected? },
      logger: ->(message) { Rails.logger.warn(message) }
    )
  end

  def screenshot_publisher
    @screenshot_publisher ||= ObsBridge::ScreenshotCommandPublisher.new(
      sns: Aws::SNS::Client.new(**config.event_pipeline.aws_client_options),
      topology: config.orinoco.messaging_topology
    )
  end

  def gate
    @gate ||= D2r::CaptureGate.new(redis: Redis.new(url: config.scoreboard.redis_url))
  end

  def obs_bridge_connected?
    status = obs_bridge_status_reader.snapshot.fetch(:status)
    heartbeat_at = status[:last_heartbeat_at]
    status.fetch(:connected, false) && heartbeat_at && heartbeat_at > Time.now.utc - BRIDGE_HEARTBEAT_STALE_AFTER_SECONDS
  end

  def obs_bridge_status_reader
    @obs_bridge_status_reader ||= ObsBridge::StatusReader.new(
      redis: Redis.new(url: config.scoreboard.redis_url),
      bridge_id: config.obs_bridge.bridge_id || "obs_bridge"
    )
  end

  def install_signal_handlers
    @stop_requested = false
    %w[INT TERM].each { |signal| Signal.trap(signal) { @stop_requested = true } }
  end

  def config
    Rails.configuration.x
  end
end
