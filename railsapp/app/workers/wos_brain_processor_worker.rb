# frozen_string_literal: true

require_relative "../services/orinoco/pipeline"
require_relative "../services/wos/screenshot_event_handler"
require_relative "../services/wos/status_store"

class WosBrainProcessorWorker
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
    handler = Wos::ScreenshotEventHandler.new(
      config_reader: -> { AffordanceConfig.fetch!(:wos_brain) },
      status_store: status_store
    )

    @definition ||= Orinoco::Pipeline.processor(:wos_brain) do
      consume Orinoco::Messaging::Names::OBS_SCREENSHOT_RESULT_QUEUE
      publish_to Orinoco::Messaging::Names::WOS_BOARD_RECOGNIZED_TOPIC

      on "obs.screenshot.captured" do |event, ctx|
        handler.call(event, ctx)
      end
    end
  end

  def sqs
    @sqs ||= Aws::SQS::Client.new(**config.event_pipeline.aws_client_options)
  end

  def sns
    @sns ||= Aws::SNS::Client.new(**config.event_pipeline.aws_client_options)
  end

  def status_store
    @status_store ||= Wos::StatusStore.new(redis: redis)
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