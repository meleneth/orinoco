# frozen_string_literal: true

require_relative "../services/orinoco/pipeline"

class ClipShowProcessorWorker
  def run
    runner.run
  end

  def run_once
    runner.run_once
  end

  private

  def runner
    @runner ||= Orinoco::Pipeline::Runner.new(
      definition: definition,
      sqs: sqs,
      sns: sns,
      topology: topology
    )
  end

  def definition
    handler = ClipShow::Handler.new(
      inventory: inventory_reader,
      config: affordance_config_reader
    )

    @definition ||= Orinoco::Pipeline.processor(:clip_show) do
      consume Orinoco::Messaging::Names::OBS_EVENTS_QUEUE
      publish_to Orinoco::Messaging::Names::OBS_COMMAND_TOPIC

      on "obs.media_input_playback_ended" do |event, ctx|
        handler.call(event, ctx)
      end
    end
  end

  def inventory_reader
    @inventory_reader ||= ObsBridge::InventoryReader.new(
      redis: redis,
      bridge_id: bridge_id
    )
  end

  def affordance_config_reader
    @affordance_config_reader ||= Object.new.tap do |reader|
      def reader.enabled_for_scene?(name:, scene_name:)
        record = AffordanceConfig.find_by(name: name.to_s)
        return false unless record

        config = (record.config || {}).deep_stringify_keys
        enabled = ActiveModel::Type::Boolean.new.cast(config["enabled"])
        scenes = Array(config["scenes"]).map(&:to_s)

        enabled && scenes.include?(scene_name.to_s)
      end
    end
  end

  def sqs
    @sqs ||= Aws::SQS::Client.new(**config.event_pipeline.aws_client_options)
  end

  def sns
    @sns ||= Aws::SNS::Client.new(**config.event_pipeline.aws_client_options)
  end

  def redis
    @redis ||= Redis.new(url: config.scoreboard.redis_url)
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