# frozen_string_literal: true

require_relative "../services/orinoco/pipeline"

class TwitchChatProjectionWorker
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
    handler = TwitchChatProjection::Handler.new(redis: redis)
    status_writer = twitch_status_writer

    @definition ||= Orinoco::Pipeline.processor(:twitch_chat_projection) do
      consume Orinoco::Messaging::Names::TWITCH_CHAT_MESSAGE_QUEUE

      on "twitch.chat.message_received" do |event, _ctx|
        handler.call(event)
        status_writer.clear_last_error!
      rescue StandardError => e
        status_writer.set_last_error!("Twitch chat projection failed: #{e.class}: #{e.message}")
        raise
      end
    end
  end

  def twitch_status_writer
    @twitch_status_writer ||= ObsBridge::StatusWriter.new(
      redis: redis,
      bridge_id: TwitchBridgeWorker::BRIDGE_ID
    )
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

  def config
    Rails.configuration.x
  end
end