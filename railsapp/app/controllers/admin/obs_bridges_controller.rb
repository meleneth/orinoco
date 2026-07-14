# frozen_string_literal: true

class Admin::ObsBridgesController < ApplicationController
  BRIDGES = {
    "obs_bridge" => {
      label: "OBS Bridge",
      queue_name: Orinoco::Messaging::Names::OBS_BRIDGE_CONTROL_QUEUE,
      event_prefix: "obs.bridge",
      source: "obs.bridge.control",
      refresh: true,
      capture_all: true
    },
    "twitch_bridge" => {
      label: "Twitch Bridge",
      queue_name: Orinoco::Messaging::Names::TWITCH_BRIDGE_CONTROL_QUEUE,
      event_prefix: "twitch.bridge",
      source: "twitch.bridge.control",
      refresh: false,
      capture_all: false
    },
    "7tv_bridge" => {
      label: "7TV Bridge",
      queue_name: Orinoco::Messaging::Names::SEVEN_TV_BRIDGE_CONTROL_QUEUE,
      event_prefix: "7tv.bridge",
      source: "7tv.bridge.control",
      refresh: true,
      capture_all: false
    }
  }.freeze

  def show
    @bridges = BRIDGES
    @bridge_definition = bridge_definition
    @bridge = status_reader.snapshot
  end

  def start
    status_writer.mark_start_requested
    control_publisher.start!

    redirect_back_to_bridge("#{bridge_definition.fetch(:label)} start requested.")
  rescue StandardError => e
    redirect_back_to_bridge("Failed to request bridge start: #{e.message}", alert: true)
  end

  def stop
    status_writer.mark_stop_requested
    control_publisher.stop!

    redirect_back_to_bridge("#{bridge_definition.fetch(:label)} stop requested.")
  rescue StandardError => e
    redirect_back_to_bridge("Failed to request bridge stop: #{e.message}", alert: true)
  end

  def refresh
    unless bridge_definition.fetch(:refresh)
      return redirect_back_to_bridge("#{bridge_definition.fetch(:label)} does not support inventory refresh.", alert: true)
    end

    control_publisher.refresh!
    redirect_back_to_bridge("Inventory refresh requested.")
  rescue StandardError => e
    redirect_back_to_bridge("Failed to request inventory refresh: #{e.message}", alert: true)
  end

  def capture_all
    unless bridge_definition.fetch(:capture_all)
      return redirect_back_to_bridge("#{bridge_definition.fetch(:label)} does not support event capture windows.", alert: true)
    end

    duration_seconds = params.fetch(:duration_seconds, 900)
    control_publisher.capture_all!(duration_seconds: duration_seconds)
    redirect_back_to_bridge("Capture-all requested for #{duration_seconds} seconds.")
  rescue StandardError => e
    redirect_back_to_bridge("Failed to request capture-all: #{e.message}", alert: true)
  end

  private

  def bridge_id
    params[:id].presence || Rails.application.config.x.obs_bridge.bridge_id
  end

  def bridge_definition
    BRIDGES.fetch(bridge_id) do
      raise ActionController::RoutingError, "unknown bridge #{bridge_id.inspect}"
    end
  end

  def status_reader
    ObsBridge::StatusReader.new(
      redis: redis_client,
      bridge_id: bridge_id
    )
  end

  def status_writer
    ObsBridge::StatusWriter.new(
      redis: redis_client,
      bridge_id: bridge_id
    )
  end

  def control_publisher
    ObsBridge::ControlPublisher.new(
      sqs: sqs_client,
      queue_url: control_queue_url,
      bridge_id: bridge_id,
      event_prefix: bridge_definition.fetch(:event_prefix),
      source: bridge_definition.fetch(:source)
    )
  end

  def redis_client
    @redis_client ||= Redis.new(url: Rails.application.config.x.scoreboard.redis_url)
  end

  def sqs_client
    @sqs_client ||= Aws::SQS::Client.new(**Rails.configuration.x.event_pipeline.aws_client_options)
  end

  def control_queue_url
    Rails.application.config.x.orinoco.messaging_topology
      .queue_url(bridge_definition.fetch(:queue_name))
  end

  def redirect_back_to_bridge(message, alert: false)
    flash_key = alert ? :alert : :notice
    redirect_to admin_obs_bridge_path(bridge_id), flash_key => message
  end
end
