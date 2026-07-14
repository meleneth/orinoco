# frozen_string_literal: true

require_relative "../services/orinoco/pipeline"

class SevenTvBridgeWorker
  BRIDGE_ID = "7tv_bridge"

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

    @definition ||= Orinoco::Pipeline.processor(:seven_tv_bridge) do
      consume Orinoco::Messaging::Names::SEVEN_TV_BRIDGE_CONTROL_QUEUE

      on "7tv.bridge.enable" do |_event, ctx|
        channel_name = TwitchBridgeWorker.configured_channel_name

        unless channel_name
          bridge_state.disable!
          bridge_state.set_last_error!("7TV bridge cannot start: configure a Twitch channel first")
          ctx.logger.call("[7tv-bridge] start requested without Twitch channel config")
          next
        end

        bridge_state.enable!
        ctx.start_runtime
      end

      on "7tv.bridge.disable" do |_event, ctx|
        bridge_state.disable!
        ctx.stop_runtime
        bridge_state.disconnected!
      end

      on "7tv.bridge.refresh" do |_event, ctx|
        if ctx.runtime_running?
          ctx.with_runtime(&:refresh!)
        else
          channel_name = TwitchBridgeWorker.configured_channel_name

          unless channel_name
            bridge_state.set_last_error!("7TV bridge cannot refresh: configure a Twitch channel first")
            next
          end

          SevenTvBridge::Runtime.new(
            channel_name: channel_name,
            redis: Redis.new(url: Rails.application.config.x.scoreboard.redis_url),
            logger: ctx.logger,
            refresh_interval: 0
          ).refresh!
        end
      end

      runtime do |ctx|
        SevenTvBridge::Runtime.new(
          channel_name: TwitchBridgeWorker.channel_name,
          redis: Redis.new(url: Rails.application.config.x.scoreboard.redis_url),
          logger: ctx.logger,
          on_connected: -> { bridge_state.connected! },
          on_disconnected: lambda { |error: nil|
            error ? bridge_state.disconnected!(error: error) : bridge_state.disconnected!
          }
        )
      end
    end
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
