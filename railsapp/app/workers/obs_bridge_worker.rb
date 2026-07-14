# frozen_string_literal: true

require "json"
require_relative "../services/orinoco/pipeline"

class ObsBridgeWorker
  def run
    supervisor.run
  end

  private

  def supervisor
    @supervisor ||= ObsBridge::Supervisor.new(
      state: state,
      control_consumer: control_consumer,
      command_consumer: command_consumer,
      runtime_factory: method(:build_runtime),
      signal_queue: signal_queue
    )
  end

  def build_runtime
    ObsBridge::Runtime.new(
      state: state,
      inventory_store: inventory_store,
      session_runner: build_session_runner,
      event_publisher: obs_event_publisher,
      result_publisher: obs_result_publisher,
      event_types: ["media_input_playback_ended"]
    )
  end

  def build_session_runner
    ObsBridge::ObswsSessionRunner.new(
      host: obs_host,
      port: obs_port
    )
  end

  def control_consumer
    @control_consumer ||= ObsBridge::ControlConsumer.new(
      sqs: sqs,
      queue_url: topology.queue_url(Orinoco::Messaging::Names::OBS_BRIDGE_CONTROL_QUEUE),
      bridge_id: bridge_id,
      applier: applier
    )
  end

  def command_consumer
    @command_consumer ||= ObsBridge::CommandConsumer.new(
      sqs: sqs,
      queue_url: topology.queue_url(Orinoco::Messaging::Names::OBS_BRIDGE_COMMAND_QUEUE),
      signal_queue: signal_queue
    )
  end

  def applier
    @applier ||= ObsBridge::ControlApplier.new(
      state: state,
      signal_queue: signal_queue
    )
  end

  def state
    @state ||= ObsBridge::BridgeState.new(
      redis: redis,
      bridge_id: bridge_id,
      default_enabled: config.obs_bridge.default_enabled,
      inventory_store: inventory_store
    )
  end

  def inventory_store
    @inventory_store ||= ObsBridge::InventoryStore.new(
      redis: redis,
      bridge_id: bridge_id
    )
  end

  def obs_event_publisher
    @obs_event_publisher ||= lambda do |type, payload|
      pipeline_publisher.publish(type, payload, source: "obs.websocket")
    end
  end

  def obs_result_publisher
    @obs_result_publisher ||= lambda do |type, payload, topic:, correlation:|
      screenshot_result_publisher.publish(
        type,
        payload,
        topic: topic,
        source: "obs.websocket",
        correlation: correlation
      )
    end
  end

  def screenshot_result_publisher
    @screenshot_result_publisher ||= Orinoco::Pipeline::Publisher.new(
      sns: sns,
      topology: topology,
      default_topic: Orinoco::Messaging::Names::OBS_SCREENSHOT_RESULT_TOPIC
    )
  end
  def pipeline_publisher
    @pipeline_publisher ||= Orinoco::Pipeline::Publisher.new(
      sns: sns,
      topology: topology,
      default_topic: Orinoco::Messaging::Names::OBS_EVENTS_TOPIC
    )
  end

  def sqs
    @sqs ||= Aws::SQS::Client.new(**config.event_pipeline.aws_client_options)
  end

  def sns
    @sns ||= Aws::SNS::Client.new(**config.event_pipeline.aws_client_options)
  end

  def obs_host
    obs_config = ObsConfig.first
    return obs_config.host if obs_config

    config.obs_bridge.obs_host
  end

  def obs_port
    obs_config = ObsConfig.first
    return obs_config.port if obs_config

    config.obs_bridge.obs_port
  end

  def redis
    @redis ||= Redis.new(url: Rails.application.config.x.scoreboard.redis_url)
  end

  def signal_queue
    @signal_queue ||= Queue.new
  end

  def topology
    config.orinoco.messaging_topology
  end

  def bridge_id
    config.obs_bridge.bridge_id || "obs_bridge"
  end

  def config
    Rails.configuration.x
  end
end
