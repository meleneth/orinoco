# frozen_string_literal: true

require_relative "../services/wos/screenshot_request_loop"
require_relative "../services/wos/status_store"
require_relative "../services/obs_bridge/screenshot_command_publisher"
require_relative "../services/obs_bridge/status_reader"

class WosBrainCaptureWorker
  BRIDGE_HEARTBEAT_STALE_AFTER_SECONDS = 15

  def run
    install_signal_handlers
    loop.run(stop: -> { stop_requested? })
  end

  def run_once
    loop.run_once
  end

  private

  def loop
    @loop ||= Wos::ScreenshotRequestLoop.new(
      config_reader: -> { AffordanceConfig.fetch!(:wos_brain) },
      publisher: screenshot_publisher,
      status_store: status_store,
      bridge_available: -> { obs_bridge_connected? },
      interval_seconds: interval_seconds,
      image_width: image_width,
      image_height: image_height,
      logger: ->(message) { Rails.logger.warn(message) }
    )
  end

  def obs_bridge_connected?
    status = bridge_status.fetch(:status)
    return false unless status.fetch(:connected, false)

    heartbeat_at = status[:last_heartbeat_at]
    return false unless heartbeat_at

    heartbeat_at > Time.now.utc - BRIDGE_HEARTBEAT_STALE_AFTER_SECONDS
  end

  def bridge_status
    obs_bridge_status_reader.snapshot
  end

  def obs_bridge_status_reader
    @obs_bridge_status_reader ||= ObsBridge::StatusReader.new(
      redis: redis,
      bridge_id: config.obs_bridge.bridge_id || "obs_bridge"
    )
  end
  def screenshot_publisher
    @screenshot_publisher ||= ObsBridge::ScreenshotCommandPublisher.new(
      sns: Aws::SNS::Client.new(**config.event_pipeline.aws_client_options),
      topology: topology
    )
  end

  def status_store
    @status_store ||= Wos::StatusStore.new(redis: redis)
  end

  def redis
    @redis ||= Redis.new(url: config.scoreboard.redis_url)
  end

  def topology
    config.orinoco.messaging_topology
  end

  def interval_seconds
    ENV.fetch("WOS_BRAIN_SCREENSHOT_INTERVAL", Wos::ScreenshotRequestLoop::DEFAULT_INTERVAL_SECONDS).to_f
  end

  def image_width
    ENV.fetch("WOS_BRAIN_SCREENSHOT_WIDTH", Wos::ScreenshotRequestLoop::DEFAULT_IMAGE_WIDTH).to_i
  end

  def image_height
    ENV.fetch("WOS_BRAIN_SCREENSHOT_HEIGHT", Wos::ScreenshotRequestLoop::DEFAULT_IMAGE_HEIGHT).to_i
  end

  def install_signal_handlers
    @stop_requested = false
    %w[INT TERM].each do |signal|
      Signal.trap(signal) { @stop_requested = true }
    end
  end

  def stop_requested?
    @stop_requested == true
  end

  def config
    Rails.configuration.x
  end
end
