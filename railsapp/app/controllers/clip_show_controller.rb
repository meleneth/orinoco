# frozen_string_literal: true

require "json"
require_relative "../services/orinoco/pipeline"

class ClipShowController < ApplicationController
  layout :resolve_layout

  def play
    index_to_play = params[:id]
    clip_name     = params[:clip_name]
    scene_name    = params[:scene_name]

    obs_request_emitter.call(
      "requestType" => "SetSceneItemEnabled",
      "requestData" => {
        "sceneName" => scene_name,
        "sceneItemId" => index_to_play.to_i,
        "sceneItemEnabled" => true
      }
    )

    obs_request_emitter.call(
      "requestType" => "SetInputAudioMonitorType",
      "requestData" => {
        "inputName" => clip_name,
        "monitorType" => "OBS_MONITORING_TYPE_MONITOR_ONLY"
      }
    )

    respond_to do |format|
      format.turbo_stream { render turbo_stream: [] }
      format.html { redirect_to clip_show_path }
    end
  end

  def get_scenes
    @scenes = Hash.new
    @scene_name = params[:scenes]
    @scene_names = inventory_reader.scenes.map { |s| s.fetch("sceneName") }

    @clips = []

    if @scene_name.present?
      clip_cache = SceneIndex.new(scene: @scene_name)
      clip_cache.load_from_inventory!(inventory_reader)
      @clips = clip_cache.by_name
    end
  end

  private

  def inventory_reader
    @inventory_reader ||= ObsBridge::InventoryReader.new(
      redis: redis,
      bridge_id: bridge_id
    )
  end

  def obs_request_emitter
    @obs_request_emitter ||= lambda do |request|
      sns.publish(
        topic_arn: topology.topic_arn(Orinoco::Messaging::Names::OBS_COMMAND_TOPIC),
        message: JSON.generate(
          Orinoco::Pipeline::Event.build(
            "obs.command.requested",
            { "request" => request },
            source: "clip_show"
          ).to_h
        )
      )
    end
  end

  def sns
    @sns ||= Aws::SNS::Client.new(**app_config.event_pipeline.aws_client_options)
  end

  def redis
    @redis ||= Redis.new(url: app_config.scoreboard.redis_url)
  end

  def topology
    app_config.orinoco.messaging_topology
  end

  def bridge_id
    app_config.obs_bridge.bridge_id
  end

  def app_config
    Rails.configuration.x
  end

  def resolve_layout
    turbo_frame_request? ? false : "application"
  end
end