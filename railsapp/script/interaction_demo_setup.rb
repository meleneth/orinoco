#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../config/environment"

redis = Redis.new(url: Rails.configuration.x.scoreboard.redis_url)
topology = Rails.configuration.x.orinoco.messaging_topology

inventory_reader = ObsBridge::InventoryReader.new(
  redis: redis,
  bridge_id: Rails.configuration.x.obs_bridge.bridge_id
)

control_publisher = ObsBridge::ControlPublisher.new(
  sqs: Aws::SQS::Client.new(**Rails.configuration.x.event_pipeline.aws_client_options),
  queue_url: topology.queue_url(Orinoco::Messaging::Names::OBS_BRIDGE_CONTROL_QUEUE),
  bridge_id: Rails.configuration.x.obs_bridge.bridge_id
)

command_publisher = InteractionDemo::ObsCommandPublisher.new(
  sns: Aws::SNS::Client.new(**Rails.configuration.x.event_pipeline.aws_client_options),
  topology:
)

external_host = ENV.fetch("INTERACTION_DEMO_HOST", "127.0.0.1")
external_port = ENV.fetch("ORINOCO_WEB_PORT", "31050")
external_base_url = "http://#{external_host}:#{external_port}"

puts "[interaction_demo_setup] configuring OBS demo scene for #{external_base_url}"

InteractionDemo::ObsSetup.new(
  inventory_reader:,
  control_publisher:,
  command_publisher:,
  external_base_url:
).call

puts "[interaction_demo_setup] requested scene=#{InteractionDemo::ObsSetup::SCENE_NAME} input=#{InteractionDemo::ObsSetup::WEB_SOURCE_NAME}"
