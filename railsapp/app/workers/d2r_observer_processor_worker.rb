# frozen_string_literal: true

require_relative "../services/d2r/capture_gate"
require_relative "../services/d2r/scan_presence"
require_relative "../services/d2r/screenshot_event_handler"
require_relative "../services/orinoco/pipeline"

class D2rObserverProcessorWorker
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
      sqs: Aws::SQS::Client.new(**config.event_pipeline.aws_client_options),
      sns: Aws::SNS::Client.new(**config.event_pipeline.aws_client_options),
      topology: config.orinoco.messaging_topology
    )
  end

  def definition
    handler = D2r::ScreenshotEventHandler.new(
      config_reader: -> { AffordanceConfig.fetch!(:d2r_observer) },
      gate: D2r::CaptureGate.new(redis: Redis.new(url: config.scoreboard.redis_url)),
      presence: D2r::ScanPresence.new(redis: Redis.new(url: config.scoreboard.redis_url))
    )

    @definition ||= Orinoco::Pipeline.processor(:d2r_observer) do
      consume Orinoco::Messaging::Names::D2R_SCREENSHOT_RESULT_QUEUE, wait_time_seconds: 1
      publish_to Orinoco::Messaging::Names::D2R_EVENTS_TOPIC

      on "obs.screenshot.captured" do |event, context|
        handler.call(event, context)
      end
    end
  end

  def config
    Rails.configuration.x
  end
end
