# frozen_string_literal: true

require_relative "../services/d2r/capture_gate"
require_relative "../services/d2r/observer_control"
require_relative "../services/d2r/scan_presence"
require_relative "../services/d2r/screenshot_request_loop"
require_relative "../services/interaction_demo/obs_command_publisher"
require_relative "../services/interaction_demo/obs_setup"
require_relative "../services/obs_bridge/control_publisher"
require_relative "../services/obs_bridge/inventory_reader"
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
      presence: D2r::ScanPresence.new(redis: Redis.new(url: config.scoreboard.redis_url)),
      observer_control: D2r::ObserverControl.new(redis: Redis.new(url: config.scoreboard.redis_url)),
      bridge_available: -> { obs_bridge_ready? },
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

  def obs_bridge_ready?
    return false unless obs_bridge_connected?

    ensure_overlay_configured!
    true
  rescue StandardError => e
    Rails.logger.warn("[d2r/overlay-setup] #{e.class}: #{e.message}")
    false
  end

  def ensure_overlay_configured!
    return if @overlay_configured

    overlay_setup.call
    @overlay_configured = true
  end

  def overlay_setup
    @overlay_setup ||= InteractionDemo::ObsSetup.new(
      inventory_reader: ObsBridge::InventoryReader.new(
        redis: Redis.new(url: config.scoreboard.redis_url),
        bridge_id: config.obs_bridge.bridge_id
      ),
      control_publisher: ObsBridge::ControlPublisher.new(
        sqs: Aws::SQS::Client.new(**config.event_pipeline.aws_client_options),
        queue_url: config.orinoco.messaging_topology.queue_url(Orinoco::Messaging::Names::OBS_BRIDGE_CONTROL_QUEUE),
        bridge_id: config.obs_bridge.bridge_id
      ),
      command_publisher: InteractionDemo::ObsCommandPublisher.new(
        sns: Aws::SNS::Client.new(**config.event_pipeline.aws_client_options),
        topology: config.orinoco.messaging_topology
      ),
      external_base_url: ENV.fetch("ORINOCO_OVERLAY_BASE_URL", "http://127.0.0.1:31050"),
      placement_scene_names: [ InteractionDemo::ObsSetup::SCENE_NAME, ENV.fetch("D2R_OVERLAY_SCENE_NAME", "Game") ]
    )
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
