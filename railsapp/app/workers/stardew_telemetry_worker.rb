# frozen_string_literal: true
require_relative "../services/orinoco/pipeline"

class StardewTelemetryWorker
  def run
    config = Rails.configuration.x
    projection = Stardew::TelemetryProjection.new(redis: Redis.new(url: config.scoreboard.redis_url))
    definition = Orinoco::Pipeline.processor(:stardew_telemetry) do
      consume Orinoco::Messaging::Names::STARDEW_EVENTS_QUEUE, wait_time_seconds: 1
      on("stardew.snapshot") { |event, _context| projection.call(event) }
    end
    Orinoco::Pipeline::Runner.new(
      definition: definition,
      sqs: Aws::SQS::Client.new(**config.event_pipeline.aws_client_options),
      sns: Aws::SNS::Client.new(**config.event_pipeline.aws_client_options),
      topology: config.orinoco.messaging_topology
    ).run
  end
end
