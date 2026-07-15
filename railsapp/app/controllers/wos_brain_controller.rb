# frozen_string_literal: true

class WosBrainController < ApplicationController
  skip_before_action :ensure_obs_config!

  def show
    load_dashboard
  end

  def start
    config = AffordanceConfig.fetch!(:wos_brain)
    config.enabled = true
    config.save!
    status_store.update!("state" => "enabled", "last_error" => "")

    redirect_to wos_brain_path, notice: "WOSBrain enabled"
  end

  def stop
    config = AffordanceConfig.fetch!(:wos_brain)
    config.enabled = false
    config.save!
    status_store.disabled!

    redirect_to wos_brain_path, notice: "WOSBrain disabled"
  end

  private

  def load_dashboard
    @config = AffordanceConfig.fetch!(:wos_brain)
    @status = status_store.read
    @overlay_state = overlay_state_store.read
    @obs_bridge_status = obs_bridge_status
    @pipeline_queues = pipeline_queues
    @status_age_seconds = status_age_seconds(@status["updated_at"])
  end

  def status_age_seconds(value)
    return nil if value.blank?

    (Time.now.utc - Time.iso8601(value)).round
  rescue ArgumentError
    nil
  end
  def status_store
    @status_store ||= Wos::StatusStore.new(redis: redis)
  end

  def overlay_state_store
    @overlay_state_store ||= Wos::OverlayStateStore.new(redis: redis)
  end

  def obs_bridge_status
    ObsBridge::StatusReader.new(
      redis: redis,
      bridge_id: Rails.configuration.x.obs_bridge.bridge_id || "obs_bridge"
    ).snapshot.fetch(:status)
  rescue StandardError => e
    { connected: false, runtime_state: "unknown", desired_state: "unknown", last_error: "#{e.class}: #{e.message}" }
  end

  def pipeline_queues
    names = [
      Orinoco::Messaging::Names::OBS_BRIDGE_COMMAND_QUEUE,
      Orinoco::Messaging::Names::OBS_SCREENSHOT_RESULT_QUEUE,
      Orinoco::Messaging::Names::WOS_BOARD_RECOGNIZED_QUEUE
    ]
    snapshots = queue_inspector.queues
    names.filter_map { |name| snapshots.find { |queue| queue.name == name } }
  rescue StandardError
    []
  end

  def queue_inspector
    @queue_inspector ||= Orinoco::Messaging::QueueInspector.new(
      sqs: Aws::SQS::Client.new(**Rails.configuration.x.event_pipeline.aws_client_options),
      topology: Rails.configuration.x.orinoco.messaging_topology
    )
  end

  def redis
    @redis ||= Redis.new(url: Rails.configuration.x.scoreboard.redis_url)
  end
end
