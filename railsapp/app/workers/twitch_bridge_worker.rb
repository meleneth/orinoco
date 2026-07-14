# frozen_string_literal: true

require_relative "../services/orinoco/pipeline"

class TwitchBridgeWorker
  BRIDGE_ID = "twitch_bridge"

  def run
    state
    runner.run
  end

  def run_once
    state
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
    bridge_state = state
    seven_tv_publisher = seven_tv_control_publisher

    @definition ||= Orinoco::Pipeline.processor(:twitch_bridge) do
      consume Orinoco::Messaging::Names::TWITCH_BRIDGE_CONTROL_QUEUE
      publish_to Orinoco::Messaging::Names::TWITCH_CHAT_MESSAGE_TOPIC

      on "twitch.bridge.enable" do |_event, ctx|
        channel_name = TwitchBridgeWorker.configured_channel_name

        unless channel_name
          bridge_state.disable!
          bridge_state.set_last_error!("Twitch bridge cannot start: configure a Twitch channel first")
          ctx.logger.call("[twitch-bridge] start requested without Twitch channel config")
          next
        end

        bridge_state.enable!
        seven_tv_publisher.start!
        ctx.start_runtime
      end

      on "twitch.bridge.disable" do |_event, ctx|
        bridge_state.disable!
        seven_tv_publisher.stop!
        ctx.stop_runtime
        bridge_state.disconnected!
      end

      runtime do |ctx|
        TwitchChatBridge::Runtime.new(
          channel_name: TwitchBridgeWorker.channel_name,
          logger: ctx.logger,
          on_connected: -> { bridge_state.connected! },
          on_disconnected: -> { bridge_state.disconnected! },
          publisher: lambda do |message|
            ctx.publish("twitch.chat.message_received", message.as_json, source: "twitch.chat")
          end
        )
      end
    end
  end

  def self.channel_name
    configured_channel_name || raise(KeyError, "configure Twitch channel before starting bridge")
  end

  def self.configured_channel_name
    config = TwitchConfig.first
    return config.channel_name if config&.channel_name.present?
    return ENV["TWITCH_CHANNEL_NAME"] if ENV["TWITCH_CHANNEL_NAME"].present?

    nil
  end

  def seven_tv_control_publisher
    @seven_tv_control_publisher ||= ObsBridge::ControlPublisher.new(
      sqs: sqs,
      queue_url: topology.queue_url(Orinoco::Messaging::Names::SEVEN_TV_BRIDGE_CONTROL_QUEUE),
      bridge_id: SevenTvBridgeWorker::BRIDGE_ID,
      event_prefix: "7tv.bridge",
      source: "7tv.bridge.control"
    )
  end

  def state
    @state ||= ObsBridge::BridgeState.new(
      redis: redis,
      bridge_id: BRIDGE_ID,
      default_enabled: false
    )
  end

  def redis
    @redis ||= Redis.new(url: Rails.application.config.x.scoreboard.redis_url)
  end

  def sqs
    @sqs ||= Aws::SQS::Client.new(**config.event_pipeline.aws_client_options)
  end

  def sns
    @sns ||= Aws::SNS::Client.new(**config.event_pipeline.aws_client_options)
  end

  def topology
    config.orinoco.messaging_topology
  end

  def config
    Rails.configuration.x
  end
end
