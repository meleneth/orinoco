# frozen_string_literal: true

require_relative "../services/orinoco/pipeline"
require_relative "../services/wos_projection/handler"

class WosBrainProjectionWorker
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
    handler = WosProjection::Handler.new(redis: redis)

    @definition ||= Orinoco::Pipeline.processor(:wos_brain_projection) do
      consume Orinoco::Messaging::Names::WOS_BOARD_RECOGNIZED_QUEUE

      on "wos.board.recognized" do |event, _ctx|
        handler.call(event)
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

  def config
    Rails.configuration.x
  end
end