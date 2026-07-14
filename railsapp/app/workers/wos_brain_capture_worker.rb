# frozen_string_literal: true

require_relative "../services/wos/screenshot_request_loop"
require_relative "../services/wos/status_store"
require_relative "../services/obs_bridge/screenshot_command_publisher"

class WosBrainCaptureWorker
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
      interval_seconds: interval_seconds,
      image_width: image_width,
      image_height: image_height,
      logger: ->(message) { Rails.logger.warn(message) }
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